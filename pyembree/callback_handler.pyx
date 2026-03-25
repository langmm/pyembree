# distutils: language=c++
from pyembree.rtcore_ray cimport RTCRayHit

cdef class RayCollisionCallback:
    cdef int callback(self, RTCRayHit &ray):
        return CALLBACK_TERMINATE
