; PMOMS - a tiny 64-bit graphical hobby OS for BIOS/VirtualBox.
; Bootable 1.44 MiB floppy image. Stage 1 loads the rest of this binary,
; stage 2 selects a VESA linear framebuffer and enters x86-64 long mode.

BITS 16
ORG 0x7C00

STAGE2_SEG equ 0x0800
STAGE2_OFF equ 0x0000
STAGE2_SECTORS equ 63
STACK_TOP equ 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_TOP
    sti
    mov [boot_drive], dl

    ; Load sectors 2..64 from the boot floppy into 0000:8000.
    mov ax, STAGE2_SEG
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, STAGE2_SECTORS
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [boot_drive]
    int 0x13
    jc disk_error
    jmp STAGE2_SEG:STAGE2_OFF

disk_error:
    mov si, disk_msg
.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .print
.halt:
    hlt
    jmp .halt

boot_drive db 0
disk_msg db 'PMOMS disk read failed', 0

times 510-($-$$) db 0
dw 0xAA55

; ---------------- Stage 2 ----------------
stage2:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov ax, 0x9000
    mov es, ax
    mov di, 0
    mov word [vesa_mode], 0x4118 ; 1024x768x32 + linear framebuffer
    mov ax, 0x4F01
    mov cx, [vesa_mode]
    int 0x10
    cmp ax, 0x004F
    je .mode_info_ok
    mov word [vesa_mode], 0x4115 ; fallback: 800x600x32
    mov cx, [vesa_mode]
    mov ax, 0x4F01
    int 0x10
    cmp ax, 0x004F
    jne vesa_error
.mode_info_ok:
    mov eax, [es:0x28]
    mov [lfb_phys], eax
    mov ax, [es:0x12]
    mov [screen_w], ax
    mov ax, [es:0x14]
    mov [screen_h], ax
    mov ax, [es:0x10]
    mov [pitch], ax

    mov ax, 0x4F02
    mov bx, [vesa_mode]
    int 0x10
    cmp ax, 0x004F
    jne vesa_error

    ; Enable A20.
    in al, 0x92
    or al, 00000010b
    out 0x92, al

    cli
    lgdt [gdt64.pointer]

    ; Identity-map the first 1 GiB with 2 MiB pages so the VESA LFB is usable.
    xor eax, eax
    mov edi, 0x1000
    mov ecx, 0x5000 / 4
    rep stosd
    mov dword [0x1000], 0x2003
    mov dword [0x2000], 0x3003
    mov edi, 0x3000
    mov eax, 0x00000083
    mov ecx, 512
.map_pd:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    loop .map_pd

    mov eax, 0x1000
    mov cr3, eax
    mov eax, cr4
    or eax, 1 << 5              ; PAE
    mov cr4, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8              ; LME
    wrmsr
    mov eax, cr0
    or eax, (1 << 31) | 1       ; paging + protected mode
    mov cr0, eax
    jmp 0x08:long_mode

vesa_error:
    mov si, vesa_msg
    mov ax, 0x0003
    int 0x10
.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .print
.halt: hlt
    jmp .halt

vesa_msg db 'PMOMS needs a VESA 32-bit linear framebuffer.', 0

ALIGN 8
gdt64:
    dq 0
.code: equ $ - gdt64
    dq 0x00AF9A000000FFFF
.data: equ $ - gdt64
    dq 0x00AF92000000FFFF
.pointer:
    dw $ - gdt64 - 1
    dq gdt64

BITS 64
long_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x70000
    call kmain
.hang:
    hlt
    jmp .hang

; rdi=x, rsi=y, rdx=w, rcx=h, r8d=color
rect:
    push rbx
    push r9
    push r10
    push r11
    movzx r9, word [screen_w]
    movzx r10, word [screen_h]
    cmp rdi, r9
    jae .done
    cmp rsi, r10
    jae .done
    mov rax, rdi
    add rax, rdx
    cmp rax, r9
    jbe .wok
    mov rdx, r9
    sub rdx, rdi
.wok:
    mov rax, rsi
    add rax, rcx
    cmp rax, r10
    jbe .hok
    mov rcx, r10
    sub rcx, rsi
.hok:
    movzx r11, word [pitch]
    mov rbx, [lfb_phys]
    mov rax, rsi
    imul rax, r11
    lea rax, [rax + rdi*4]
    add rbx, rax
    mov rdi, rbx
.y:
    push rcx
    push rbx
    mov rcx, rdx
    mov eax, r8d
    rep stosd
    pop rbx
    add rbx, r11
    mov rdi, rbx
    pop rcx
    loop .y
.done:
    pop r11
    pop r10
    pop r9
    pop rbx
    ret

; Draw a simple modern desktop: gradient, translucent-looking cards,
; dock, status bar, logo blocks, and feature tiles.
kmain:
    mov rbx, [lfb_phys]
    movzx r10, word [screen_w]
    movzx r11, word [screen_h]
    movzx r12, word [pitch]
    xor rsi, rsi
.grad_y:
    xor rdi, rdi
.grad_x:
    mov rax, rdi
    shr rax, 3
    add eax, 0x20
    mov rcx, rsi
    shr rcx, 2
    add ecx, 0x20
    mov edx, edi
    add edx, esi
    shr edx, 4
    add edx, 0x60
    cmp eax, 0xFF
    jbe .r_ok
    mov eax, 0xFF
.r_ok:
    cmp ecx, 0xFF
    jbe .g_ok
    mov ecx, 0xFF
.g_ok:
    cmp edx, 0xFF
    jbe .b_ok
    mov edx, 0xFF
.b_ok:
    shl eax, 16
    shl ecx, 8
    or eax, ecx
    or eax, edx
    mov [rbx + rdi*4], eax
    inc rdi
    cmp rdi, r10
    jb .grad_x
    add rbx, r12
    inc rsi
    cmp rsi, r11
    jb .grad_y

    ; top bar
    mov rdi, 0
    mov rsi, 0
    movzx rdx, word [screen_w]
    mov rcx, 42
    mov r8d, 0x151822
    call rect
    ; left glass panel
    mov rdi, 42
    mov rsi, 72
    mov rdx, 300
    mov rcx, 610
    mov r8d, 0x202638
    call rect
    ; main window
    mov rdi, 380
    mov rsi, 92
    mov rdx, 590
    mov rcx, 430
    mov r8d, 0xF0F4FF
    call rect
    mov rdi, 380
    mov rsi, 92
    mov rdx, 590
    mov rcx, 56
    mov r8d, 0x141927
    call rect
    ; colorful cards
    mov rdi, 414
    mov rsi, 182
    mov rdx, 240
    mov rcx, 130
    mov r8d, 0x5B7CFA
    call rect
    mov rdi, 690
    mov rsi, 182
    mov rdx, 240
    mov rcx, 130
    mov r8d, 0x16C79A
    call rect
    mov rdi, 414
    mov rsi, 342
    mov rdx, 516
    mov rcx, 138
    mov r8d, 0xFFB86B
    call rect
    ; dock
    mov rdi, 260
    movzx rsi, word [screen_h]
    sub rsi, 78
    mov rdx, 504
    mov rcx, 54
    mov r8d, 0x111827
    call rect
    ; app icons
    mov r9, 290
.icons:
    mov rdi, r9
    movzx rsi, word [screen_h]
    sub rsi, 66
    mov rdx, 34
    mov rcx, 34
    mov r8d, 0xEAF0FF
    call rect
    add r9, 58
    cmp r9, 740
    jb .icons
    ; PMOMS block logo on panel
    mov rdi, 82
    mov rsi, 112
    mov rdx, 48
    mov rcx, 48
    mov r8d, 0x6EE7F9
    call rect
    mov rdi, 138
    mov rsi, 112
    mov rdx, 48
    mov rcx, 48
    mov r8d, 0xA78BFA
    call rect
    mov rdi, 82
    mov rsi, 168
    mov rdx, 104
    mov rcx, 24
    mov r8d, 0xF472B6
    call rect
    ; hardware/modern technology tiles: x86-64, VESA, ACPI, PCIe, USB, NET
    mov rdi, 78
    mov rsi, 245
    mov rdx, 224
    mov rcx, 44
    mov r8d, 0x334155
    call rect
    mov rdi, 78
    mov rsi, 305
    mov rdx, 224
    mov rcx, 44
    mov r8d, 0x475569
    call rect
    mov rdi, 78
    mov rsi, 365
    mov rdx, 224
    mov rcx, 44
    mov r8d, 0x334155
    call rect
    mov rdi, 78
    mov rsi, 425
    mov rdx, 224
    mov rcx, 44
    mov r8d, 0x475569
    call rect
    ; CPU feature marker: green if long mode is live.
    mov rdi, 912
    mov rsi, 14
    mov rdx, 20
    mov rcx, 14
    mov r8d, 0x22C55E
    call rect
    jmp $

vesa_mode dw 0x4118
lfb_phys dq 0
screen_w dw 1024
screen_h dw 768
pitch dw 4096

times (64*512)-($-$$) db 0
