cmake_minimum_required(VERSION 3.19)
project(caelestia-blobs VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Quick ShaderTools)
qt_standard_project_setup(REQUIRES 6.8)

set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")

qt_add_qml_module(caelestia-blobs
    URI Caelestia.Blobs
    VERSION 1.0
    SOURCES
        src/blobgroup.cpp    src/blobgroup.hpp
        src/blobshape.cpp    src/blobshape.hpp
        src/blobrect.cpp     src/blobrect.hpp
        src/blobinvertedrect.cpp src/blobinvertedrect.hpp
        src/blobmaterial.cpp src/blobmaterial.hpp
)

qt_add_shaders(caelestia-blobs "blob_shaders"
    BATCHABLE OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    FILES
        src/shaders/blob.frag
        src/shaders/blob.vert
)

target_include_directories(caelestia-blobs PRIVATE src)
target_link_libraries(caelestia-blobs PRIVATE Qt::Core Qt::Qml Qt::Quick)

# Install to user QML path so Quickshell finds Caelestia.Blobs
set(INSTALL_QMLDIR "$ENV{HOME}/.local/lib/qt6/qml" CACHE STRING "QML install dir")
install(TARGETS caelestia-blobs caelestia-blobsplugin
    LIBRARY DESTINATION "${INSTALL_QMLDIR}/Caelestia/Blobs"
    RUNTIME DESTINATION "${INSTALL_QMLDIR}/Caelestia/Blobs"
)
install(FILES
    "${CMAKE_BINARY_DIR}/qml/Caelestia/Blobs/qmldir"
    "${CMAKE_BINARY_DIR}/qml/Caelestia/Blobs/Caelestia.Blobs.qmltypes"
    DESTINATION "${INSTALL_QMLDIR}/Caelestia/Blobs"
)
