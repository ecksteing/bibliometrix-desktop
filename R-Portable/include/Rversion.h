/* Rversion.h.  Generated automatically. */
#ifndef R_VERSION_H
#define R_VERSION_H

#ifdef __cplusplus
extern "C" {
#endif

#define R_VERSION 263681
#define R_NICK "Happy Hop"
#define R_Version(v,p,s) (((v) * 65536) + ((p) * 256) + (s))
#define R_MAJOR  "4"
#define R_MINOR  "6.1"
#define R_STATUS ""
#define R_YEAR   "2026"
#define R_MONTH  "06"
#define R_DAY    "24"
#define R_SVN_REVISION 90187
#ifdef __llvm__
# define R_FILEVERSION    4,61,24651,0
#else
# define R_FILEVERSION    4,61,90187,0
#endif

#ifdef __cplusplus
}
#endif

#endif /* not R_VERSION_H */
