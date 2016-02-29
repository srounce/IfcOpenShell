FIND_PACKAGE(SWIG)
IF(NOT SWIG_FOUND)
	MESSAGE(FATAL_ERROR "BUILD_IFCPYTHON enabled, but unable to find SWIG. Disable BUILD_IFCPYTHON or fix SWIG paths to proceed.")
ENDIF()

INCLUDE(${SWIG_USE_FILE})

find_package (Nodejs REQUIRED)

include_directories (
  ${NODEJS_INCLUDE_DIRS}
  ${CMAKE_CURRENT_SOURCE_DIR}
)

# SWIG treats SWIG_FLAGS as a list and not a string so semicolon seperation is
# required. This hardcodes V8_VERSION to be <10 but I assume that's not going
# to be a problem for a little while! SWIG uses a padded SWIG_V8 version which
# we hack together from our findnode module.
set (V8_VERSION_HEX 0x0${V8_VERSION_MAJOR}${V8_VERSION_MINOR}${V8_VERSION_PATCH})
string (LENGTH "${V8_VERSION_HEX}" V8_VERSION_HEX_length)
while (V8_VERSION_HEX_length LESS 8)
  set (V8_VERSION_HEX "${V8_VERSION_HEX}0")
  message (DEBUG " - Padded V8 version to match SWIG format")
  string (LENGTH "${V8_VERSION_HEX}" V8_VERSION_HEX_length)
endwhile ()

set_property (SOURCE ifcopenshelljs.i PROPERTY SWIG_FLAGS "-node" "-includeall"
  "-I${CMAKE_CURRENT_SOURCE_DIR}/.." "-DV8_VERSION=${V8_VERSION_HEX}")
set_source_files_properties (ifcopenshelljs.i PROPERTIES CPLUSPLUS ON)

swig_add_module (ifcopenshelljs javascript ifcopenshelljs.i ${ifcopenshell_LIB_SRCS})
swig_link_libraries (ifcopenshelljs  IfcParse IfcGeom ${PYTHON_LIBRARIES} ${OPENCASCADE_LIBRARIES} ${ICU_LIBRARIES})

set_target_properties (ifcopenshelljs PROPERTIES
  COMPILE_FLAGS " -DBUILDING_NODE_EXTENSION -DSWIGJAVASCRIPT=${SWIG_FOUND}"
  PREFIX ""
  OUTPUT_NAME ifcopenshell
  SUFFIX ".node"
)

message (INFO " - swig Version ${SWIG_VERSION}")
message (INFO " - CXX compiler Version ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")

if (${V8_VERSION_MAJOR} GREATER 3)
  message (INFO " - Using V8 version > 3 so requiring C++11 compiler")
  # Node 0.12.x V8 engine major version is '3'.
  # Node 2.1.0  V8 engine major version is '4'.
  set_property (TARGET ifcopenshelljs PROPERTY CXX_STANDARD 11)
  set_property (TARGET ifcopenshelljs PROPERTY CXX_STANDARD_REQUIRED ON)
  if(CMAKE_VERSION VERSION_LESS "3.1")
    message(INFO " - **WARNING** Need to use CMAKE version 3.1+, but it is ${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION}.${CMAKE_PATCH_VERSION}")
    message(INFO " -             So a workaround will be used.")
    if(CMAKE_COMPILER_IS_GNUCXX)
      if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS "4.7")
        message(FATAL_ERROR " FATAL ERROR: GNU gcc compiler is also too old (need 4.7+, but ${CMAKE_CXX_COMPILER_VERSION}) and does not support C++11 standard.")
      endif()
      set(IFCOPENSHELL_CXX11_WORKAROUND_OPTION "-std=gnu++11")
    else()
      set(IFCOPENSHELL_CXX11_WORKAROUND_OPTION "-std=c++11")
    endif()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${IFCOPENSHELL_CXX11_WORKAROUND_OPTION} ")
  endif()
endif ()

macro (ifcopenshell_CREATE_INSTALL_PACKAGE_JSON generated_file install_location)
  configure_file (${generated_file}.cmake ${CMAKE_CURRENT_BINARY_DIR}/${generated_file} @ONLY)
  install (FILES ${CMAKE_CURRENT_BINARY_DIR}/${generated_file} DESTINATION ${install_location})
endmacro (ifcopenshell_CREATE_INSTALL_PACKAGE_JSON)
ifcopenshell_create_install_package_json (package.json lib/node_modules/ifcopenshell)

macro (ifcopenshell_CREATE_BINDING_GYP generated_file)
  set (ifcopenshell_LIB_SRCS_GYP "")
  set (ifcopenshell_NPM_SRCS ${ifcopenshell_LIB_SRCS_NOAUTO}
                     ${ifcopenshell_LIB_ARM_SRCS_NOAUTO}
                     ${ifcopenshell_LIB_X86_SRCS_NOAUTO}
  )
  foreach (srcfile ${ifcopenshell_NPM_SRCS})
    file (RELATIVE_PATH rel ${CMAKE_CURRENT_SOURCE_DIR} ${srcfile})
    set (ifcopenshell_LIB_SRCS_GYP "'${rel}',\n${ifcopenshell_LIB_SRCS_GYP}")
  endforeach (srcfile)
  foreach (includedir ${ifcopenshell_LIB_INCLUDE_DIRS})
    file (RELATIVE_PATH rel ${CMAKE_CURRENT_SOURCE_DIR} ${includedir})
    set (ifcopenshell_LIB_INCLUDE_DIRS_GYP "'${rel}',\n${ifcopenshell_LIB_INCLUDE_DIRS_GYP}")
  endforeach (includedir)
  configure_file (${generated_file}.cmake ${CMAKE_CURRENT_BINARY_DIR}/${generated_file} @ONLY)
endmacro (ifcopenshell_CREATE_BINDING_GYP)
ifcopenshell_create_binding_gyp (binding.gyp)

add_custom_target (npmpkg)
add_custom_command (TARGET npmpkg POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_CURRENT_BINARY_DIR}/ifcopenshelljsJAVASCRIPT_wrap.cxx ${CMAKE_SOURCE_DIR}/src
        COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_BINARY_DIR}/src/version.c ${CMAKE_SOURCE_DIR}/src
        COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_CURRENT_BINARY_DIR}/package.json ${CMAKE_SOURCE_DIR}
        COMMAND sed -i "'s/ifcopenshell.node/build\\/Release\\/ifcopenshell.node/'"
        ${CMAKE_SOURCE_DIR}/package.json
        COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_CURRENT_BINARY_DIR}/binding.gyp ${CMAKE_SOURCE_DIR}
        COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_SOURCE_DIR}/docs/npm.md ${CMAKE_SOURCE_DIR}/READMEFIRST)
add_dependencies (npmpkg ifcopenshelljs)

#install (FILES ${CMAKE_CURRENT_BINARY_DIR}/ifcopenshell.node
         #DESTINATION lib/node_modules/ifcopenshell)
