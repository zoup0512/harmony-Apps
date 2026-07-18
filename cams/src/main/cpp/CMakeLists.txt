cmake_minimum_required(VERSION 3.5.0)
project(rtspencoder)

add_compile_options(-D_FORTIFY_SOURCE=2 -O2)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(rtspencoder SHARED
    napi_init.cpp
    video_encoder_engine.cpp
)

target_link_libraries(rtspencoder PUBLIC
    libace_napi.z.so
    libace_ndk.z.so
    libnative_media_venc.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libnative_window.so
    libhilog_ndk.z.so
)
