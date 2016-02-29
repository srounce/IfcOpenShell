{
  'targets': [
    {
    'target_name': 'ifcopenshell',
    'sources': [
      @ifcopenshell_LIB_SRCS_GYP@
      'src/version.c',
      'src/ifcopenshelljsJAVASCRIPT_wrap.cxx' ],
      'include_dirs': [
        @ifcopenshell_LIB_INCLUDE_DIRS_GYP@
      ],
      'variables': {
        "v8_version%": "<!(node -e 'console.log(process.versions.v8)' | sed 's/\.//g' | cut -c 1-5)",
          "arch%": "<!(node -e 'console.log(process.arch)')"
      },
      'cflags_cc!': [ '-fno-rtti', '-fno-exceptions' ],
      'cflags!': [ '-fno-exceptions' ],
      'conditions' : [
        [ 'arch=="x64"',
          { 'defines' : [ 'X86PLAT=ON' ], },
      ],
      [ 'arch=="ia32"',
        { 'defines' : [ 'X86PLAT=ON'], },
      ],
      [ 'arch=="arm"',
        { 'defines' : [ 'ARMPLAT=ON'], },
      ],
      ],
      'defines' : [ 'SWIG',
        'SWIGJAVASCRIPT',
        'BUILDING_NODE_EXTENSION=1',
        'SWIG_V8_VERSION=0x0<(v8_version)',
        'V8_VERSION=0x0<(v8_version)'
      ]
  }
  ]
}
