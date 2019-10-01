ENTRY(start)

SECTIONS
{
    physicalKernelOffset = 0xFFFFFFFFC0000000;
    . = physicalKernelOffset + 1M;

    .text ALIGN(4K) : AT(ADDR(.text) - physicalKernelOffset)
    {
        KEEP(*(.multiboot))
        KEEP(*(.text*))
    }

    .rodata ALIGN(4K) : AT(ADDR(.rodata) - physicalKernelOffset)
    {
        KEEP(*(.rodata*))
    }

    .data ALIGN(4K) : AT(ADDR(.data) - physicalKernelOffset)
    {
        KEEP(*(.data*))
    }

    .bss ALIGN(4K) : AT(ADDR(.bss) - physicalKernelOffset)
    {
        KEEP(*(COMMON))
        KEEP(*(.bss))
    }
}