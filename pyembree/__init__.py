from importlib import metadata
from pyembree import rtcore

__version__ = metadata.version('pyembree')
__embree_version__ = rtcore._embree_version
