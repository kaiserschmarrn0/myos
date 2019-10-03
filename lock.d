module lock;

import core.atomic : atomicOp, atomicLoad, atomicStore;

import jank;
import io;

enum uint max_spins = 0x4000000;
enum uint backoff_min = 1;

struct lock {
    shared ubyte cur = 0;
    shared ubyte next = 0;
}

void acquire(shared lock *l) {
    ubyte t = atomicOp!"+="(l.next, 1);
    t--;

    while(true) {
        ubyte c = atomicLoad(l.cur);
        if (c == t) {
            return;
        }

        const size_t len = backoff_min * (t - c);
        for (size_t j = 0; j < len; j++) {
            asm {
                rep;
                nop;
            }
        }
    }
}

void release(shared lock *l) {
    ubyte next = cast(ubyte)(atomicLoad(l.cur) + 1);
    atomicStore(l.cur, next);
}