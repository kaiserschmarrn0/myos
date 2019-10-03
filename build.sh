#!/bin/sh

NAME="myos"
IMAGE="${NAME}.elf"
ISO="${NAME}.iso"

elf() {
    AS="nasm"
    ASFLAGS="-f elf64"
    REALFLAGS="-f bin"

    ${AS} real_init.real.asm ${REALFLAGS} -o real_init.bin
    ${AS} flush_irqs.real.asm ${REALFLAGS} -o flush_irqs.bin
    ${AS} e820.real.asm ${REALFLAGS} -o e820.bin
    
    ${AS} start.asm ${ASFLAGS} -o start.o
    ${AS} real.asm ${ASFLAGS} -o real.o

    DC="ldc2"
    DFLAGS="-O2 -de -gc -d-debug -mtriple=x86_64-unknown-elf -relocation-model=static -code-model=kernel -mattr=-sse,-sse2,-sse3,-ssse3 -disable-red-zone -betterC -op -I=src"

    ${DC} ${DFLAGS} -c main.d main.o
    ${DC} ${DFLAGS} -c lock.d lock.o
    ${DC} ${DFLAGS} -c io.d io.o
    ${DC} ${DFLAGS} -c jank.d jank.o
    ${DC} ${DFLAGS} -c interrupt.d interrupt.o

    LD="ld.lld"
    LDFLAGS="-O2 -gc-sections --oformat elf_amd64 --Bstatic --nostdlib -T linker.ld"

    ${LD} ${LDFLAGS} start.o real.o main.o io.o lock.o jank.o interrupt.o -o ${IMAGE}
}

iso() {
    elf

    mkdir -p isodir/boot/grub
    cp ${IMAGE} isodir/boot/${IMAGE}
    cp grub.cfg isodir/boot/grub/grub.cfg
    sed -i "s/NAME/${NAME}/g" isodir/boot/grub/grub.cfg
    sed -i "s/IMAGE/${IMAGE}/g" isodir/boot/grub/grub.cfg
    grub-mkrescue -o ${ISO} isodir
    rm -rf isodir
}

vr() {
    iso

    VR="qemu-system-x86_64"
    VRFLAGS="-smp 4 -drive file=${ISO},index=0,media=disk,format=raw -debugcon stdio -enable-kvm -cpu host"

    ${VR} ${VRFLAGS}
}

clean() {
    rm *.o
    rm *.elf
    rm *.iso
    rm *.bin
}

set -e
$1