// Header/ABI check only; this does not link or exercise implementations.
#include <cstdint>
#include <type_traits>
#include "custom_types.h"
#include "generated/GVRSystem.gen.h"
static_assert(!std::is_abstract_v<CVRSystem_026>);
static_assert(sizeof(vr::VREvent_t) == 64);
static_assert(sizeof(vr::TrackedDevicePose_t) == 80);
#include "generated/GVRApplications.gen.h"
static_assert(!std::is_abstract_v<CVRApplications_008>);
#include "generated/GVRCompositor.gen.h"
static_assert(!std::is_abstract_v<CVRCompositor_029>);
#include "generated/GVROverlay.gen.h"
static_assert(!std::is_abstract_v<CVROverlay_028>);
#include "generated/GVRInput.gen.h"
static_assert(!std::is_abstract_v<CVRInput_011>);
