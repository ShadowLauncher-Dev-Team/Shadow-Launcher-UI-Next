if(NOT DEFINED UI_NEXT_DIR)
    message(FATAL_ERROR "UI_NEXT_DIR is required")
endif()

file(GLOB_RECURSE qml_files LIST_DIRECTORIES false "${UI_NEXT_DIR}/*.qml")
set(violations "")

foreach(qml_file IN LISTS qml_files)
    file(READ "${qml_file}" content)
    foreach(pattern
            "backend\\."
            "#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]"
            "duration *: *[0-9]"
            "z *: *[0-9]"
            "StyleTokens"
            "AnimationTokens")
        string(REGEX MATCH "${pattern}" match "${content}")
        if(NOT match STREQUAL "")
            list(APPEND violations "${qml_file}: forbidden pattern '${pattern}'")
        endif()
    endforeach()
endforeach()

if(violations)
    list(JOIN violations "\n  " violation_text)
    message(FATAL_ERROR "UI Next contract violations:\n  ${violation_text}")
endif()

message(STATUS "UI Next contract check passed (${qml_files})")
