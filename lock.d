module lock;

import core.atomic : atomicOp, atomicLoad, atomicStore;

import jank;
import io;

enum uint max_spins = 0x4000000;
enum uint backoff_min = 1;

alias ticket = ubyte;

struct lock {
    shared ticket cur = 0;
    shared ticket next = 0;
}

void acquire(shared lock *l) {
    ticket t = atomicOp!"+="(l.next, 1);
    t--;

    while(true) {
        ticket c = atomicLoad(l.cur);
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
    ticket next = cast(ticket)(atomicLoad(l.cur) + 1);
    atomicStore(l.cur, next);
}