pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Calculator for the launcher. A query is a calculation when it starts with "="
// or is plain arithmetic ("12*1.2"). A built-in parser handles arithmetic, a few
// functions and constants (it never evaluates the text as code); anything it
// can't parse goes to `qalc` (libqalculate) when installed, for units,
// conversions and currencies ("= 5 km to miles"). Trying the parser first keeps
// the math documented in the launcher's help consistent, as qalc has its own
// conventions (e.g. "%" is a percentage there).
QtObject {
    id: root

    readonly property bool   hasQalc: DependencyService.available("qalc")
    readonly property string _q: LauncherService.query.trim()

    // Expression to evaluate, "" when the query isn't a calculation.
    readonly property string expr: {
        if (_q.startsWith("=")) return _q.slice(1).trim()
        // Bare arithmetic only: anything with letters stays an app search.
        if (/^[-+(]*[0-9.,]+[0-9.,\s()]*[-+*/^%x×÷][0-9.,\s()+\-*/^%x×÷]*$/.test(_q)) return _q
        return ""
    }
    readonly property bool active: expr !== ""

    property string result: ""        // formatted result, "" while unknown/invalid
    property string hint:   ""        // why qalc gave no result
    // Words the built-in parser doesn't know (units, currencies…): only qalc can help.
    readonly property bool needsQalc: !hasQalc
        && (expr.match(/[a-z]+/gi) ?? []).some(w => _fns[w.toLowerCase()] === undefined && _consts[w.toLowerCase()] === undefined)
    property bool   busy:   false

    onExprChanged: {
        result = ""
        hint = ""
        _debounce.stop()
        if (expr === "") return
        result = _evalBuiltin(expr)
        if (result === "" && hasQalc) _debounce.restart()
    }

    // ── qalc ─────────────────────────────────────────────────────────────────
    // Conversions ("X to Y") also ask qalc for X alone, without its automatic
    // conversion ("1 EUR" would become "$1.14"): when the result equals it, the
    // target wasn't understood ("1 EUR to pound" → "€1", pound being a mass).
    readonly property var _convRe: /\s(?:to|->|→)\s/i
    property Timer _debounce: Timer {
        interval: 120
        onTriggered: {
            root.busy = true
            const e = root._qalcExpr(root.expr)
            const parts = e.split(root._convRe)
            root._qalc.command = parts.length > 1
                ? ["sh", "-c", 'qalc -t -- "$1"; printf "\\036\\n"; qalc -t -s "conv 0" -- "$2"', "sh", e, parts[0]]
                : ["qalc", "-t", "--", e]
            root._qalc.running = false
            root._qalc.running = true
        }
    }
    property Process _qalc: Process {
        property string _for: ""
        onStarted: _for = root.expr
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                if (root._qalc._for !== root.expr) return   // a newer query is pending
                const [full, base] = text.split("\x1e").map(x => x.trim().split("\n").pop().trim())
                const nows = x => (x ?? "").replace(/\s/g, "")
                const conversion = base !== undefined
                const bad = full === "" || /error|warning/i.test(full)
                         // A word qalc doesn't know is split into unit symbols and
                         // prefixes, giving a formula ("1€ to yuan" → "(1E24 / n) × …").
                         || /[(×·]/.test(full)
                         || nows(full) === nows(root.expr)
                         || (conversion && nows(full) === nows(base))
                root.result = bad ? "" : full
                root.hint = !bad ? ""
                          : conversion ? "Unknown unit or currency (currencies use ISO codes: USD, EUR, CNY…)"
                          : "Can't calculate this"
            }
        }
    }

    // Common currency names qalc doesn't know (it reads them as unit symbols).
    readonly property var _aliases: ({ yuan: "CNY", renminbi: "CNY", rmb: "CNY" })
    // "to -unit" asks qalc for a plain value instead of mixed units
    // ("3.107 mi" rather than "3 mi + 188 yd + 2.39 in").
    // Temperatures in any case, with or without "°"/"deg": qalc is case-sensitive
    // and reads bare letters as other units (C coulomb, F farad, c speed of
    // light, f femto, k kilo). Only the exact "<number> <temp> to <temp>" form is
    // rewritten, so "3e8 m/s to c" keeps its meaning.
    readonly property var _tempRe: /^\s*([-+]?[\d.,]+)\s*(?:°|deg)?\s*(c|f|k|celsius|fahrenheit|kelvin)\s+(?:to|->|→|in)\s+(?:°|deg)?\s*(c|f|k|celsius|fahrenheit|kelvin)\s*$/i
    function _tempUnit(u) { const c = u[0].toLowerCase(); return c === "c" ? "°C" : c === "f" ? "°F" : "K" }
    function _qalcExpr(e) {
        const t = e.match(_tempRe)
        if (t) e = t[1].replace(",", ".") + " " + _tempUnit(t[2]) + " to " + _tempUnit(t[3])
        const named = e.replace(/[a-z]+/gi, w => _aliases[w.toLowerCase()] ?? w)
        return named.replace(/(\s(?:to|->|→)\s+)(?![-+])/i, "$1-")
    }

    // ── Built-in parser ──────────────────────────────────────────────────────
    // Recursive descent over: + - * / % ^, parentheses, unary minus, a few
    // functions (sqrt, sin, cos, tan, asin, acos, atan, ln, log, abs, round,
    // floor, ceil, exp) and constants (pi, e). "," is accepted as a decimal point.
    readonly property var _fns: ({
        sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, tan: Math.tan,
        asin: Math.asin, acos: Math.acos, atan: Math.atan, ln: Math.log,
        log: Math.log10, abs: Math.abs, round: Math.round, floor: Math.floor,
        ceil: Math.ceil, exp: Math.exp
    })
    readonly property var _consts: ({ pi: Math.PI, "π": Math.PI, e: Math.E })

    function _evalBuiltin(src) {
        // "x" only means "times" between numbers (so "exp" stays a function name).
        // Split before dropping spaces, so "2 2" stays two numbers (an error).
        const norm = src.replace(/,/g, ".").replace(/(\d)\s*x\s*(?=[\d(])/gi, "$1*")
                        .replace(/×/g, "*").replace(/÷/g, "/")
        const toks = norm.match(/\d*\.?\d+(?:e[-+]?\d+)?|[a-zπ]+|[-+*/^%()]/gi)
        if (!toks || toks.join("") !== norm.replace(/\s/g, "")) return ""   // unknown characters
        let i = 0
        const peek = () => toks[i]
        const next = () => toks[i++]
        const expect = t => { if (next() !== t) throw 0 }

        function expression() {
            let v = term()
            while (peek() === "+" || peek() === "-") v = next() === "+" ? v + term() : v - term()
            return v
        }
        function term() {
            let v = unary()
            while (peek() === "*" || peek() === "/" || peek() === "%") {
                const op = next(), r = unary()
                v = op === "*" ? v * r : op === "/" ? v / r : v % r
            }
            return v
        }
        function unary() {
            if (peek() === "-") { next(); return -unary() }
            if (peek() === "+") { next(); return unary() }
            return power()
        }
        function power() {
            const b = primary()
            if (peek() === "^") { next(); return Math.pow(b, unary()) }   // right-associative
            return b
        }
        function primary() {
            const t = next()
            if (t === undefined) throw 0
            if (t === "(") { const v = expression(); expect(")"); return v }
            if (/^[\d.]/.test(t)) return parseFloat(t)
            const name = t.toLowerCase()
            if (root._consts[name] !== undefined) return root._consts[name]
            if (root._fns[name]) { expect("("); const v = expression(); expect(")"); return root._fns[name](v) }
            throw 0
        }

        try {
            const v = expression()
            if (i !== toks.length || !isFinite(v)) return ""
            return _format(v)
        } catch (e) {
            return ""
        }
    }

    function _format(v) {
        if (Number.isInteger(v) && Math.abs(v) < 1e15) return "" + v
        const s = Math.abs(v) >= 1e15 || Math.abs(v) < 1e-6 ? v.toExponential(10) : v.toPrecision(12)
        // Drop trailing zeros of the fraction (and of the mantissa in exponent form).
        return s.replace(/(\.\d*?)0+(e|$)/, "$1$2").replace(/\.(e|$)/, "$1")
    }

    // ── Copy ─────────────────────────────────────────────────────────────────
    property Process _copy: Process {}
    function copy() {
        if (result === "") return
        _copy.command = ["wl-copy", "--", result.replace(/−/g, "-")]   // qalc's Unicode minus
        _copy.running = false
        _copy.running = true
    }
}
