module lock;

import core.atomic : atomicOp, atomicLoad, atomicStore;

import jank;
import io;

struct lock {
    enum uint max_spins = 0x4000000;
    enum uint backoff_min = 1;

    alias ticket = ubyte;

    shared ticket cur = 0;
    shared ticket next = 0;

    shared void acquire() {
        ticket t = atomicOp!"+="(next, 1);

        for(int i = 0; i < max_spins; i++) {
            if (atomicLoad(cur) != t) {
                return;
            }

            size_t len = t - cur;
            size_t j = backoff_min * len;
            for (; j > 0 && i < max_spins; j--, i++) {
                asm {
                    rep;
                    nop;
                }
            }
        }

        panic("possible deadlock after %u spins.\n", max_spins);
    }

    shared void release() {
        ubyte next = cast(ubyte)(atomicLoad(cur) + 1);
        atomicStore(cur, next);
    }
}