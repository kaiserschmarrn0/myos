module jank;

import io;

extern(C):
@system:

void __assert(const(char)* exp, const(char)* file, uint line) {
    panic("assertion failed: %s: %u: %s", file, 0, exp);
}

/*void _d_array_slice_copy(void* dst, size_t dstlen, void* src, size_t srclen, size_t elemsz) {
        import ldc.intrinsics : llvm_memcpy;
        llvm_memcpy!size_t(dst, src, dstlen * elemsz, 0);
}*/

pure int memcmp(scope const void* str1, scope const void* str2, size_t n) {
    ubyte* s1 = cast(ubyte*)str1;
    ubyte* s2 = cast(ubyte*)str2;
    
    while (n-- > 0) {
        if (*s1++ != *s2++) {
            return s1[-1] < s2[-1] ? -1 : 1;
        }
    }

    return 0;
}

/*pure void* memcpy(return void* str1, scope const void* str2, size_t n) {
    ubyte *s1 = cast(ubyte*)str1;
    ubyte *s2 = cast(ubyte*)str2;

    for (int i = 0; i < n; i++) {
        s1[i] = s2[i];
    }

    return s1;
}*/

pure void* memset(return void* s, int c, size_t n) {
    ubyte* ptr = cast(ubyte*)s;

    for (int i = 0; i < n; i++) {
        ptr[i] = cast(ubyte)c;
    }

    return s;
}