/* bitten SDK: CoreGraphics base definitions. Written from the public
 * documentation. */
#ifndef BITTEN_CGBASE_H
#define BITTEN_CGBASE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>

#define CG_EXTERN extern
#define CG_ENUM(_type, _name) enum __attribute__((enum_extensibility(open))) _name : _type _name; \
    enum __attribute__((enum_extensibility(open))) _name : _type
#define CG_OPTIONS(_type, _name) enum __attribute__((enum_extensibility(open), flag_enum)) _name : _type _name; \
    enum __attribute__((enum_extensibility(open), flag_enum)) _name : _type
#define CG_BRIDGED_TYPE(T) CF_BRIDGED(T)
#define CG_ASSUME_BEGIN _Pragma("clang arc_cf_code_audited begin") _Pragma("clang assume_nonnull begin")
#define CG_ASSUME_END _Pragma("clang assume_nonnull end") _Pragma("clang arc_cf_code_audited end")
#endif
