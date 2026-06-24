pragma Singleton
import QtQuick
import "."

// Wallhaven.cc search client (QML XMLHttpRequest, no curl). SFW-only unless an
// API key is set (wallpaper.wallhavenKey). Results are thumbnail + full URLs;
// downloading the chosen full image to disk is WallpaperService's job (curl).
QtObject {
    id: root

    property var    results:  []     // [{ id, thumb, full, resolution, fileType }]
    property bool   loading:  false
    property string error:    ""
    property int    page:     1
    property int    lastPage: 1
    readonly property bool hasMore: page < lastPage

    property string _query:   ""
    property string _sorting: "toplist"   // toplist | date_added | views | favorites | random | relevance

    function search(query, sorting) {
        _query   = query   !== undefined ? ("" + query)   : _query
        _sorting = sorting !== undefined ? ("" + sorting) : _sorting
        results  = []
        _fetch(1, false)
    }
    function loadMore() { if (!loading && hasMore) _fetch(page + 1, true) }

    function _fetch(p, append) {
        loading = true
        error   = ""
        const key = SettingsService.get("wallpaper.wallhavenKey", "")
        let url = "https://wallhaven.cc/api/v1/search?purity=100"
                + "&sorting=" + encodeURIComponent(root._sorting)
                + "&page=" + p
        if (root._query !== "") url += "&q=" + encodeURIComponent(root._query)
        if (key !== "")         url += "&apikey=" + encodeURIComponent(key)

        const xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        xhr.open("GET", url)
        // Wallhaven 403s requests with no/empty User-Agent.
        xhr.setRequestHeader("User-Agent", "Mozilla/5.0 quickshell-wallpaper")
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            root.loading = false
            if (xhr.status !== 200) { root.error = "Wallhaven: HTTP " + xhr.status; return }
            let j
            try { j = JSON.parse(xhr.responseText) } catch (e) { root.error = "Wallhaven: bad response"; return }
            const rows = (j.data || []).map(w => ({
                id:         w.id,
                thumb:      (w.thumbs && (w.thumbs.small || w.thumbs.large)) || "",
                full:       w.path,
                resolution: w.resolution,
                fileType:   w.file_type
            }))
            root.page     = (j.meta && j.meta.current_page) || p
            root.lastPage = (j.meta && j.meta.last_page) || p
            root.results  = append ? root.results.concat(rows) : rows
        }
        xhr.send()
    }
}
