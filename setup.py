#!/usr/bin/env python
from setuptools import setup

import os
import numpy as np
from Cython.Build import cythonize

include_path = [np.get_include()]

ext_modules = cythonize(
    'pyembree/*.pyx',
    include_path=include_path,
    compiler_directives={'language_level': 2},
)
for ext in ext_modules:
    ext.include_dirs = include_path
    ext.libraries = ["embree4"]
    if os.name == "nt":
        # It is recommended to build against tbb and tbbmalloc, which may improve
        # the library's runtime performance. However, to be a 'manylinux' wheel, these
        # must be removed for maximum portability.
        #
        # See also `ci/embree_linux.bash`
        #
        ext.libraries += [
            "tbb",
            "tbbmalloc",
        ]

setup(
    ext_modules=ext_modules,
)
