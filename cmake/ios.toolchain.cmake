# iOS toolchain for WoWee: arm64 Simulator (default) or arm64 device.
#
# -DWOWEE_IOS_PLATFORM=simulator  -> SDK iphonesimulator, ejecutable para el
#                                   simulador del Mac.
# -DWOWEE_IOS_PLATFORM=device     -> SDK iphoneos, binario instalable en un
#                                   iPhone real (necesita firma con un Apple ID).
#
# Vulkan is provided by MoltenVK, linked statically. SDL's UIKit Vulkan driver
# resolves vkGetInstanceProcAddr through RTLD_DEFAULT (see SDL_uikitvulkan.m),
# so no Vulkan loader dylib or ICD manifest is required on either platform.
#
# Usage (deps vendored in ios/libs[-device]; every path below can be
# overridden on the command line):
#   cmake -S . -B build-ios \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
#     -DWOWEE_IOS_PLATFORM=device \
#   cmake --build build-ios --target wowee -j 4

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(WOWEE_IOS_PLATFORM "simulator" CACHE STRING
    "iOS platform: 'simulator' (Mac) or 'device' (physical iPhone)")
if(WOWEE_IOS_PLATFORM STREQUAL "device")
    set(CMAKE_OSX_SYSROOT iphoneos)
else()
    set(CMAKE_OSX_SYSROOT iphonesimulator)
endif()
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# The iOS platform sets CMAKE_FIND_ROOT_PATH to the SDK, which by default
# limits all find_* searches to that root. Allow vcpkg deps (installed outside
# the SDK) to be found too.
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# Never let pkg-config resolve host (macOS/Homebrew) packages for the iOS build.
# NB: empty-string values are treated as "unset" by CMake, so point at a
# nonexistent directory instead.
set(ENV{PKG_CONFIG_LIBDIR} "/nonexistent/ios-pkgconfig")
set(ENV{PKG_CONFIG_PATH} "/nonexistent/ios-pkgconfig")

# CPack install rules are macOS/Linux/Windows packaging specific; not used on
# iOS (we assemble the .app bundle manually).
set(CMAKE_SKIP_INSTALL_RULES TRUE)

# Vendored deps in the repo: ios/libs for the simulator, ios/libs-device for
# the device. Override with -D... on the command line when the deps live
# elsewhere.
set(_wowee_ios_deps "${CMAKE_CURRENT_LIST_DIR}/../ios/libs")
if(WOWEE_IOS_PLATFORM STREQUAL "device")
    set(_wowee_ios_deps "${CMAKE_CURRENT_LIST_DIR}/../ios/libs-device")
endif()

if(NOT DEFINED WOWEE_MOLTENVK_ROOT)
    set(WOWEE_MOLTENVK_ROOT "${_wowee_ios_deps}/moltenvk")
endif()
if(NOT DEFINED WOWEE_MOLTENVK_LIB)
    set(WOWEE_MOLTENVK_LIB "${WOWEE_MOLTENVK_ROOT}/libMoltenVK.a")
endif()
if(NOT DEFINED WOWEE_VCPKG_INSTALLED)
    # Headers de Vulkan: iguales para simulador y dispositivo.
    set(WOWEE_VCPKG_INSTALLED "${CMAKE_CURRENT_LIST_DIR}/../ios/libs/vulkan")
endif()

# Vendored iOS deps: SDL3 and OpenSSL live under the per-platform dir, glm and
# the Vulkan headers are shared in ios/libs, so a plain
# `cmake -B build-ios -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake`
# configures without any external script.
list(APPEND CMAKE_PREFIX_PATH
    "${_wowee_ios_deps}/sdl3" "${_wowee_ios_deps}/openssl"
    "${CMAKE_CURRENT_LIST_DIR}/../ios/libs/glm"
    "${CMAKE_CURRENT_LIST_DIR}/../ios/libs/vulkan")

if(EXISTS "${WOWEE_MOLTENVK_LIB}" AND NOT TARGET Vulkan::Vulkan)
    message(STATUS "MoltenVK: ${WOWEE_MOLTENVK_LIB}")
    add_library(Vulkan::Vulkan STATIC IMPORTED)
    set_target_properties(Vulkan::Vulkan PROPERTIES
        IMPORTED_LOCATION "${WOWEE_MOLTENVK_LIB}")
    # Vulkan headers come from vcpkg's vulkan-headers.
    set_property(TARGET Vulkan::Vulkan APPEND PROPERTY
        INTERFACE_INCLUDE_DIRECTORIES "${WOWEE_VCPKG_INSTALLED}/include")
    # Frameworks required by MoltenVK/SDL on iOS. -ObjC is needed so
    # Objective-C classes/categories in the static libraries are loaded.
    set_property(TARGET Vulkan::Vulkan APPEND PROPERTY
        INTERFACE_LINK_LIBRARIES
            "-framework Metal"
            "-framework Foundation"
            "-framework UIKit"
            "-framework QuartzCore"
            "-framework CoreGraphics"
            "-framework IOKit"
            "-framework IOSurface"
            "-framework CoreText"
            "-framework ImageIO"
            "-framework Security"
            "-framework AudioToolbox"
            "-framework CoreAudio"
            "-framework CoreVideo"
            "-framework OpenGLES"
            "-ObjC")
    set(Vulkan_FOUND TRUE)
elseif(NOT TARGET Vulkan::Vulkan)
    # MoltenVK not built yet (also hit by CMake compiler try_compile runs).
    # Configuration proceeds; the real link only succeeds once libMoltenVK.a
    # exists at WOWEE_MOLTENVK_LIB.
    message(WARNING
        "MoltenVK static library not found at ${WOWEE_MOLTENVK_LIB}; "
        "Vulkan::Vulkan is a no-op placeholder. Build it with: "
        "cd ${WOWEE_MOLTENVK_ROOT} && ./fetchDependencies && make iossim "
        "(or 'make ios' for a physical device)")
    add_library(Vulkan::Vulkan INTERFACE IMPORTED)
    set(Vulkan_FOUND TRUE)
endif()
