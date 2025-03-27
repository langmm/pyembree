# distutils: language=c++
from rtcore_ray cimport RTCRayHit

cdef class RayCollisionCallback:
    cdef int callback(self, RTCRayHit &ray):
        return CALLBACK_TERMINATE
