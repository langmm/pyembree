# distutils: language=c++
cimport cython
cimport numpy as np
import numpy as np
import logging
import numbers
cimport rtcore as rtc
cimport rtcore_ray as rtcr
cimport rtcore_geometry as rtcg
from .callback_handler cimport \
    RayCollisionCallback, RayCollisionNull, CALLBACK_TERMINATE, CALLBACK_CONTINUE


log = logging.getLogger('pyembree')

cdef void error_printer(void* userPtr, const rtc.RTCError code, const char *_str) noexcept:
    """
    error_printer function depends on embree version
    Embree 2.14.1
    -> cdef void error_printer(const rtc.RTCError code, const char *_str):
    Embree 2.17.1
    -> cdef void error_printer(void* userPtr, const rtc.RTCError code, const char *_str):
    """
    log.error("ERROR CAUGHT IN EMBREE")
    rtc.print_error(code)
    log.error("ERROR MESSAGE: %s" % _str)


cdef class EmbreeScene:
    def __init__(self, rtc.EmbreeDevice device=None):
        if device is None:
            # We store the embree device inside EmbreeScene to avoid premature deletion
            self.device = rtc.EmbreeDevice()
            device = self.device
        rtc.rtcSetDeviceErrorFunction(device.device, error_printer, NULL)
        self.scene_i = rtcNewScene(device.device)
        # , RTC_SCENE_STATIC, RTC_INTERSECT1)
        self.is_committed = 0

    def run(self, np.ndarray[np.float32_t, ndim=2] vec_origins,
                  np.ndarray[np.float32_t, ndim=2] vec_directions,
                  dists=None,query='INTERSECT',output=None,
                  RayCollisionCallback callback_handler=None):

        if self.is_committed == 0:
            rtcCommitScene(self.scene_i)
            self.is_committed = 1

        if callback_handler is None:
            callback_handler = RayCollisionNull()

        cdef int nv = vec_origins.shape[0]
        cdef int vo_i, vd_i, vd_step
        cdef np.ndarray[np.int32_t, ndim=1] intersect_ids
        cdef np.ndarray[np.float32_t, ndim=1] tfars
        cdef rayQueryType query_type

        if query == 'INTERSECT':
            query_type = intersect
        elif query == 'OCCLUDED':
            query_type = occluded
        elif query == 'DISTANCE':
            query_type = distance

        else:
            raise ValueError("Embree ray query type %s not recognized." 
                "\nAccepted types are (INTERSECT,OCCLUDED,DISTANCE)" % (query))

        if dists is None:
            tfars = np.empty(nv, 'float32')
            tfars.fill(1e37)
        elif isinstance(dists, numbers.Number):
            tfars = np.empty(nv, 'float32')
            tfars.fill(dists)
        else:
            tfars = dists

        if output:
            u = np.empty(nv, dtype="float32")
            v = np.empty(nv, dtype="float32")
            Ng = np.empty((nv, 3), dtype="float32")
            primID = np.empty(nv, dtype="int32")
            geomID = np.empty(nv, dtype="int32")
        else:
            intersect_ids = np.empty(nv, dtype="int32")

        cdef rtcr.RTCRayHit rayhit
        cdef int do_continue
        vd_i = 0
        vd_step = 1
        # If vec_directions is 1 long, we won't be updating it.
        if vec_directions.shape[0] == 1: vd_step = 0

        for i in range(nv):
            rayhit.ray.org_x = vec_origins[i, 0]
            rayhit.ray.org_y = vec_origins[i, 1]
            rayhit.ray.org_z = vec_origins[i, 2]
            rayhit.ray.dir_x = vec_directions[vd_i, 0]
            rayhit.ray.dir_y = vec_directions[vd_i, 1]
            rayhit.ray.dir_z = vec_directions[vd_i, 2]
            rayhit.ray.tnear = 0.0
            rayhit.ray.tfar = tfars[i]
            rayhit.ray.id = rtcg.RTC_INVALID_GEOMETRY_ID
            rayhit.hit.geomID = rtcg.RTC_INVALID_GEOMETRY_ID
            rayhit.hit.primID = rtcg.RTC_INVALID_GEOMETRY_ID
            rayhit.hit.instID[0] = rtcg.RTC_INVALID_GEOMETRY_ID
            rayhit.ray.mask = -1
            rayhit.ray.time = 0
            vd_i += vd_step

            if query_type == intersect or query_type == distance:
                do_continue = CALLBACK_CONTINUE
                while do_continue == CALLBACK_CONTINUE:
                    rtcIntersect1(self.scene_i, &rayhit, NULL)
                    do_continue = callback_handler.callback(rayhit)
                if not output:
                    if query_type == intersect:
                        intersect_ids[i] = rayhit.hit.primID
                    else:
                        tfars[i] = rayhit.ray.tfar
                else:
                    primID[i] = rayhit.hit.primID
                    geomID[i] = rayhit.hit.geomID
                    u[i] = rayhit.hit.u
                    v[i] = rayhit.hit.v
                    tfars[i] = rayhit.ray.tfar
                    Ng[i, 0] = rayhit.hit.Ng_x
                    Ng[i, 1] = rayhit.hit.Ng_y
                    Ng[i, 2] = rayhit.hit.Ng_z
            else:
                rtcOccluded1(self.scene_i, &rayhit.ray, NULL)
                intersect_ids[i] = rayhit.hit.geomID

        if output:
            return {'u':u, 'v':v, 'Ng': Ng, 'tfar': tfars, 'primID': primID, 'geomID': geomID}
        else:
            if query_type == distance:
                return tfars
            else:
                return intersect_ids

    def __dealloc__(self):
        rtcReleaseScene(self.scene_i)
