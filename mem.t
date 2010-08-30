.so book.mac
.ig
  this is even rougher than most chapters
  talk a little about initial page table conditions:
    paging not on, but virtual mostly mapped direct to physical,
    which is what things look like when we turn paging on as well
    since paging is turned on after we create first process.
  mention why still have SEG_UCODE/SEG_UDATA?
  do we ever really say what the low two bits of %cs do?
    in particular their interaction with PTE_U
  i worry that we often say "process" when it is not clear whether
    we're talking about running in user space or in the kernel
    e.g. "a process isn't allowed to look at the kernel's memory"
  talk about why there are three main*() routines in main.c?
..
.chapter CH:MEM "Processes"
.PP
One of an operating system's central roles
is to allow multiple programs to share the CPUs
and main memory safely, isolating them so that
one errant program cannot break others.
To that end, xv6 provides the concept of a process,
as described in Chapter \*[CH:UNIX].
This chapter examines how xv6 allocates
memory to hold process code and data,
how it creates a new process,
and how it configures the processor's paging
hardware to give each process the illusion that
it has a private memory address space.
The next few chapters will examine how xv6 uses hardware
support for interrupts and context switching to create
the illusion that each process has its own private CPU.
.\"
.section "Address Spaces"
.\"
.PP
xv6 ensures that each user process can only read and write the memory that
xv6 has allocated to it, and not for example the kernel's memory or
the memory of other processes. xv6 also arranges for each process's
user memory to be contiguous and to start at virtual address zero. The C
language definition and the Gnu linker expect process memory to be
contiguous. Process memory starts at zero because that is what Unix
has always done. A process's view of memory is called an address space.
.PP
x86 protected mode defines three kinds of addresses. Executing
software generates
virtual addresses when it fetches instructions or reads and writes
memory; instructions cannot directly use a linear or physical addresses.
The segmentation hardware translates virtual to linear addresses.
Finally, the paging hardware (when enabled) translates linear to physical
addresses. xv6 sets up the segmentation hardware so that virtual and
linear addresses are always the same: the segment descriptors
all have a base of zero and the maximum possible limit.
xv6 sets up the x86 paging hardware to translate (or "map") linear to physical
addresses in a way that implements process address spaces with
the properties outlined above.
.PP
The paging hardware uses a page table to translate linear to
physical addresses. A page table is logically an array of 2^20
(1,048,576) page table entries (PTEs). Each PTE contains a
20-bit physical page number (PPN) and some flags. The paging
hardware translates a linear address by using its top 20 bits
to index into the page table to find a PTE, and replacing
those bits with the PPN in the PTE.  The paging hardware
copies the low 12 bits unchanged from the linear to the
translated physical address.  Thus a page table gives
the operating system control over linear-to-physical address translations
at the granularity of aligned chunks of 4096 (2^12) bytes.
.PP
Each PTE also contains flag bits that affect how the page of linear
addresses that refer to the PTE are translated.
.code PTE_P
controls whether the PTE is valid: if it is
not set, a reference to the page causes a fault (i.e. is not allowed).
.code PTE_W
controls whether instructions are allowed to issue
writes to the page; if not set, only reads and
instruction fetches are allowed.
.code PTE_U
controls whether user programs are allowed to use the
page; if clear, only the kernel is allowed to use the page.
.PP
A few reminders about terminology.
Physical memory refers to storage cells in DRAM.
A byte of physical memory has an address, called a physical address.
A program uses virtual addresses, which the segmentation and
paging hardware translates to physical addresses, and then
sends to the DRAM system to read or write storage.
At this level of discussion there is no such thing as virtual memory.
If you want to store data in memory, you must find some
physical memory, install mappings to translate some virtual
address to the physical address of your memory, and write
your data to that virtual address.
.PP
xv6 uses page tables to implement process address spaces as
follows. Each process has a separate page table, and xv6 tells
the page table hardware to switch
page tables when xv6 switches between processes.
A process's user-accessible memory starts at linear address
zero and can have size of at most 640 kilobytes.
xv6 sets up the PTEs for the lower 640 kilobytes (i.e.,
the first 160 PTEs in the process's page table) to point
to whatever pages of physical memory xv6 has allocated for
the process's memory. xv6 sets the
.code PTE_U
bit on the first 160 PTEs so that a process can use its
own memory.
If a process has asked xv6 for less than 640 kilobytes,
xv6 will fill in fewer than 160 of these PTEs.
.PP
Different processes' page tables translate the first 160 pages to
different pages of physical memory, so that each process has
private memory.
However, xv6 sets up every process's page table to translate linear addresses
above 640 kilobytes in the same way.
To a first approximation, all processes' page tables map linear
addresses above 640 kilobytes directly to physical addresses.
However, xv6 does not set the
.code PTE_U
flag in the relevant PTEs.
This means that the kernel is allowed to use linear addresses
above 640 kilobytes, but user processes are not.
For example, the kernel can use its own instructions and data
(at linear/physical addresses starting at one megabyte).
The kernel can also read and write all the physical memory beyond
the end of its data segment, since linear addresses map directly
to physical addresses in this range.
.PP 
Note that every process's page table simultaneously contains
translations for both all of the user process's memory and all
of the kernel's memory.
This setup is very convenient: it means that xv6 can switch between
the kernel and the process when making system calls without
having to switch page tables.
For the most part the kernel does not have its own page
table; it is almost always borrowing some process's page table.
The price paid for this convenience is that the sum of the size
of the kernel and the largest process must be less than four
gigabytes on a machine with 32-bit addresses. xv6 has much
more restrictive sizes---each user process must fit in 640 kilobytes---but 
that 640 is easy to increase.
.PP
With the page table arrangement that xv6 sets up, a process can use
the lower 640 kilobytes of linear addresses, but cannot use any
other addresses---even though xv6 maps all of physical memory
in every process's page table, it sets the
.code PTE_U
bits only for addresses under 640 kilobytes.
Assuming many things (a user process can't change the page table,
xv6 never maps the same physical page into the lower 640 kilobytes
of more than one process's page table, etc.),
the result is that a process can use its own memory
but not the memory of any other process or of the kernel.
.PP
To review, xv6 ensures that each user process can only use its own memory,
and that a user process sees its memory as having contiguous addresses.
xv6 implements the first by setting the
.code PTE_U
bit only on PTEs of virtual addresses that refer to the process's own memory.
It implements the second using the ability of page tables to translate
a virtual address to a different physical address.
.\"
.section "Memory allocation"
.\"
.PP
xv6 needs to allocate physical memory at run-time to store its own data structures
and to store processes' memory. There are three main questions
to be answered when allocating memory. First,
what physical memory (i.e. DRAM storage cells) are to be used?
Second, at what linear address or addresses is the newly
allocated physical memory to be mapped? And third, how
does xv6 know what physical memory is free and what memory
is already in use?
.PP
xv6 maintains a pool of physical memory available for run-time allocation.
It uses the physical memory beyond the end of the loaded kernel's
data segment. xv6 allocates (and frees) physical memory at page (4096-byte)
granularity. It keeps a linked list of free physical pages;
xv6 deletes newly allocated pages from the list, and adds freed
pages back to the list.
.PP
When the kernel allocates physical memory that only it will use, it
does not need to make any special arrangement to be able to
refer to that memory with a linear address: the kernel sets up
all page tables so that linear addresses map directly to physical
addresses for addresses above 640 KB. Thus if the kernel allocates
the physical page at physical address 0x200000 for its internal use,
it can use that memory via linear address 0x200000 without further ado.
.PP
What if a user process allocates memory with
.code sbrk ?
Suppose that the current size of the process is 12 kilobytes,
and that xv6 finds a free page of physical memory at physical address
0x201000. In order to ensure that user process memory remains contiguous,
that physical page should appear at linear address 0x3000 when
the process is running.
This is the time (and the only time) when xv6 uses the paging hardware's
ability to translate a linear address to a different physical address.
xv6 modifies the 3rd PTE (which covers the range 0x3000 to 0x3fff)
in the process's page table
to refer to physical page number 0x201 (the upper 20 bits of 0x201000),
and sets the 
.code PTE_U
and
.code PTE_W
bits in that PTE.
Now the user process will be able to use 16 kilobytes of contiguous
memory starting at linear address zero.
Two different PTEs now refer to the physical memory at 0x201000:
the PTE for linear address 0x201000 and the PTE for linear address
0x3000. The kernel can use the memory with either of these linear
addresses; the user process can only use the second.
.\"
.section "Code: Memory allocator"
.\"
.PP
The xv6 kernel calls
.code kalloc
and
.code kfree
to allocate and free physical memory at run-time.
The kernel uses run-time allocation for user process
memory and for these kernel data strucures:
kernel stacks, pipe buffers, and page tables.
The allocator manages page-sized (4096-byte) blocks of memory.
The kernel can directly use allocated memory through a linear
address equal to the allocated memory's physical address.
.PP
.code Main
calls 
.code pminit ,
which in turn calls
.code kinit
to initialize the allocator
.line vm.c:/kinit/ .
.code pminit
ought to determine how much physical
memory is available, but this
turns out to be difficult on the x86.
.code pminit
assumes that the machine has
16 megabytes
.code PHYSTOP ) (
of physical memory, and tells
.code kinit
to use all the memory between the end of the kernel
and 
.code PHYSTOP
as the initial pool of free memory.
.PP
.code Kinit
.line kalloc.c:/^kinit/
calls
.code kfree
with the address that
.code pminit
passed to it.
This will cause
.code kfree
to add that memory to the allocator's list of free pages.
The allocator starts with no memory;
this initial call to
.code kfree
gives it some to manage.
.PP
The allocator maintains a
.italic "free list" 
of memory regions that are available
for allocation.
It keeps the list sorted in increasing
order of address in order to ease the task
of merging contiguous blocks of freed memory.
Each contiguous region of available
memory is represented by a
.code struct
.code run .
But where does the allocator get the memory
to hold that data structure?
It uses the memory being tracked 
to store the
.code run
structure tracking it.
Each
.code run
.code *r
represents the memory from address
.code (uint)r
to
.code (uint)r 
.code +
.code r->len .
The free list is
protected by a spin lock 
.line kalloc.c:/^struct/,/}/ .
The list and the lock are wrapped in a struct
to make clear that the lock protects the fields
in the struct.
For now, ignore the lock and the calls to
.code acquire
and
.code release ;
Chapter \*[CH:LOCK] will examine
locking in detail.
.PP
.code Kfree
.line kalloc.c:/^kfree/
begins by setting every byte in the 
memory being freed to the value 1.
This step is not necessary,
but it helps break incorrect code that
continues to refer to memory after freeing it.
This kind of bug is called a dangling reference.
By setting the memory to a bad value,
.code kfree
increases the chance of making such
code use an integer or pointer that is out of range
.code 0x11111111 "" (
is around 286 million).
.PP
.code Kfree 's
first real work is to store a
.code run
in the memory at
.code v .
It uses a cast in order to make
.code p ,
which is a pointer to a
.code run ,
refer to the same memory as
.code v .
It also sets
.code pend
to the
.code run
for the block following
.code v
.lines kalloc.c:/p.=..struct.run/,/pend.=/ .
If that block is free,
.code pend
will appear in the free list.
Now 
.code kfree
walks the free list, considering each run 
.code r .
The list is sorted in increasing address order, 
so the new run 
.code p
belongs before the first run
.code r
in the list such that
.code r >
.code pend .
The walk stops when either such an
.code r
is found or the list ends,
and then 
.code kfree
inserts
.code p
in the list before
.code r
.lines kalloc.c:/Insert.p.before.r/,/rp.=.p/ .
The odd-looking
.code for
loop is explained by the assignment
.code *rp
.code =
.code p :
in order to be able to insert
.code p
.italic before
.code r ,
the code had to keep track of where
it found the pointer 
.code r ,
so that it could replace that pointer with 
.code p .
The value
.code rp
points at where
.code r
came from.
.PP
There are two other cases besides simply adding
.code p
to the list.
If the new run
.code p
abuts an existing run,
those runs need to be coalesced into one large run,
so that allocating and freeing small blocks now
does not preclude allocating large blocks later.
The body of the 
.code for
loop checks for these conditions.
First, if
.code rend
.code ==
.code p
.line kalloc.c:/rend.==.p/ ,
then the run
.code r
ends where the new run
.code p
begins.
In this case, 
.code p
can be absorbed into
.code r
by increasing
.code r 's
length.
If growing 
.code r
makes it abut the next block in the list,
that block can be absorbed too
.lines "'kalloc.c:/r->next && r->next == pend/,/}/'" .
Second, if
.code pend
.code ==
.code r
.line kalloc.c:/pend.==.r/ ,
then the run 
.code p
ends where the new run
.code r
begins.
In this case,
.code r
can be absorbed into 
.code p
by increasing
.code p 's
length
and then replacing
.code r
in the list with
.code p
.lines "'kalloc.c:/pend.==.r/,/}/'" .
.PP
.code Kalloc
has a simpler job than 
.code kfree :
it walks the free list looking for
a run that is large enough to
accommodate the allocation.
When it finds one, 
.code kalloc
takes the memory from the end of the run
.lines "'kalloc.c:/r->len >= n/,/-=/'" .
If the run has no memory left,
.code kalloc
deletes the run from the list
.lines "'kalloc.c:/r->len == 0/,/rp = r->next/'"
before returning.
.\"
.section "Code: Page Table Initialization"
.\"
.PP
.code mainc
.line main.c:/kvmalloc/
creates a page table for the kernel's use with a call to
.code kvmalloc ,
and
.code mpmain
.line main.c:/vmenable/
causes the x86 paging hardware to start using that
page table with a call to 
.code vmenable .
This page table maps most virtual addresses to the same
physical address, so turning on paging with it in place does not 
disturb execution of the kernel.
.PP
.code kvmalloc
.line vm.c:/^kvmalloc/
calls
.code setupkvm
and stores a pointer to the resulting page table in
.code kpgdir ,
since it will be used later.
.PP
An x86 page table is stored in physical memory, in the form of a
4096-byte "page directory" that contains pointers to 1024
"page table pages."
Each page table page is an array of 1024 32-bit PTEs.
The page directory is also an array of 1024 PTEs, with each
physical page number referring to a page table page.
The paging hardware uses the top 10 bits of a virtual address to
select a page directory entry.
If the page directory entry is marked
.code PTE_P ,
the paging hardware uses the next 10 bits of virtual
address to select a PTE from the page table page that the
page directory entry refers to.
If the page directory entry is not valid, the paging hardware
raises a fault.
This two-level structure allows a page table to omit entire
page table pages in the common case in which large ranges of
virtual addresses have no mappings.
.PP
.code setupkvm
allocates a page of memory to hold the page directory.
It then calls
.code mappages
to install translations for ranges of memory that the kernel
will use; these translations all map a virtual address to the
same physical address.  The translations include the kernel's
instructions and data, physical memory up to
.code PHYSTOP ,
and memory ranges which are actually I/O devices.
.code setupkvm
does not install any mappings for the process's user memory;
this will happen later.
.PP
.code mappages
.line vm.c:/^mappages/
installs mappings into the page table
for a range of virtual addresses to
a corresponding range of physical addresses.
It does this separately for each virtual address in the range,
at page intervals.
For each virtual address to be mapped,
.code mappages
calls
.code walkpgdir
to find the address of the PTE that holds the address's translation.
It then initializes the PTE to hold the relevant physical page
number, the desired permissions (
.code PTE_W
and/or
.code PTE_U ),
and 
.code PTE_P
to mark the PTE as valid
.line vm.c:/perm...PTE_P/ .
.PP
.code walkpgdir
.line vm.c:/^walkpgdir/
mimics the actions of the x86 paging hardware as it
looks up the PTE for a virtual address.
It uses the upper 10 bits of the virtual address to find
the page directory entry
.line vm.c:/pde.=..pgdir/ .
If the page directory entry isn't valid, then
the required page table page hasn't yet been created;
if the
.code create
flag is set,
.code walkpgdir
goes ahead and creates it.
Finally it uses the next 10 bits of the virtual address
to find the address of the PTE in the page table page
.line vm.c:/return..pgtab/ .
The code uses the physical addresses in the page directory entries
as virtual addresses. This works because the kernel allocates
page directory pages and page table pages from an area of physical
memory (between the end of the kernel and
.code PHYSTOP)
for which the kernel has direct virtual to physical mappings.
.PP
.code vmenable
.line vm.c:/^vmenable/
loads
.code kpgdir
into the x86
.register cr3
register, which is where the hardware looks for
the physical address of the current page directory.
It then sets
.code CR0_PG
in
.register cr0
to enable paging.
.\"
.section "Code: Process creation"
.\"
.PP
This section describes how xv6 creates the very first process.
Each xv6 process has many pieces of state, which xv6 gathers
into a
.code struct
.code proc
.line proc.h:/^struct.proc/ .
A process's most important pieces of state are its user
memory, its kernel stack, and its run state.
We'll use the notation
.code p->xxx
to refer to elements of the
.code proc
structure.
.PP
.code p->pgdir
holds the process's page table, an array of PTEs.
xv6 causes the paging hardware to use a process's
.code p->pgdir
when xv6 starts running that process.
A process's page table also serves as the record of the
addresses of the physical pages that store the process's user memory.
.PP
.code p->kstack
points to the process's kernel stack.
When a process is executing in the kernel, for example in a system
call, it must have a stack on which to save variables and function
call return addresses.  xv6 allocates one kernel stack for each process.
The kernel stack is separate from the user stack, since the
user stack may not be valid.  Each process has its own kernel stack
(rather than all sharing a single stack) so that a system call may
wait (or "block") in the kernel to wait for I/O, and resume where it
left off when the I/O has finished; the process's kernel stack saves
much of the state required for such a resumption.
.PP
.code p->state 
indicates whether the process is allocated, ready
to run, running, waiting for I/O, or exiting.
.PP
The story of the creation of the first process starts when
.code mainc
.line main.c:/userinit/ 
calls
.code userinit
.line proc.c:/^userinit/ ,
whose first action is to call
.code allocproc .
The job of
.code allocproc
.line proc.c:/^allocproc/
is to allocate a slot
(a
.code struct
.code proc )
in the process table and
to initialize the parts of the process's state
required for it to execute in the kernel.
.code Allocproc 
is called for all new processes, while
.code userinit
is only called for the very first process.
.code Allocproc
scans the table for a process with state
.code UNUSED
.lines proc.c:/for.p.=.ptable.proc/,/goto.found/ .
When it finds an unused process, 
.code allocproc
sets the state to
.code EMBRYO
to mark it as used and
gives the process a unique
.code pid
.lines proc.c:/EMBRYO/,/nextpid/ .
Next, it tries to allocate a kernel stack for the
process.  If the memory allocation fails, 
.code allocproc
changes the state back to
.code UNUSED
and returns zero to signal failure.
.PP
Now
.code allocproc
must set up the new process's kernel stack.
Ordinarily processes are only created by
.code fork ,
so a new process
starts life copied from its parent.  The result of 
.code fork
is a child
that has identical user memory contents to its parent.
.code allocproc
sets up the child to 
start life running in the kernel, with a specially prepared kernel
stack and set of kernel registers that cause it to "return" to user
space at the same place (the return from the
.code fork
system call) as the parent.
.code allocproc
does part of this work by setting up return program counter
values that will cause the new process to first execute in
.code forkret
and then in
.code trapret
.lines proc.c:/uint.trapret/,/uint.forkret/ .
The new process will start running in the kernel,
with register contents copied from
.code p->context .
Thus setting
.code p->context->eip
to
.code forkret
will cause the new process to execute at
the start of the kernel function
.code forkret 
.line proc.c:/^forkret/ .
This function 
will return to whatever address is at the bottom of the stack.
The context switch code
.line swtch.S:/^swtch/
sets the stack pointer to point just beyond the end of
.code p->context .
.code allocproc
places
.code p->context
on the stack, and puts a pointer to
.code trapret
just above it; that is where
.code forkret
will return.
.code trapret
restores user registers
from values stored at the top of the kernel stack and jumps
into the user process
.line trapasm.S:/^trapret/ .
This setup is the same for ordinary
.code fork
and for creating the first process, though in
the latter case the process will start executing at
location zero rather than at a return from
.code fork .
.PP
As we will see in Chapter \*[CH:TRAP],
the way that control transfers from user software to the kernel
is via an interrupt mechanism, which is used by system calls,
interrupts, and exceptions.
Whenever control transfers into the kernel while a process is running,
the hardware and xv6 trap entry code save user registers on the
top of the process's kernel stack.
.code userinit
writes values at the top of the new stack that
look just like those that would be there if the
process had entered the kernel via an interrupt
.lines proc.c:/tf..cs.=./,/tf..eip.=./ ,
so that the ordinary code for returning from
the kernel back to the user part of a process will work.
These values are a
.code struct
.code trapframe
which stores the user registers.
.PP
Here is the state of the new process's kernel stack:
.P1
 ----------  <-- top of new process's kernel stack
| esp      |
| ...      |
| eip      |
| ...      |
| edi      | <-- p->tf (new proc's user registers)
| trapret  | <-- address forkret will return to
| eip      |
| ...      |
| edi      | <-- p->context (new proc's kernel registers)
|          |
| (empty)  |
|          |
 ----------  <-- p->kstack
.P2
.PP
The first process is going to execute a small program
.code initcode.S ; (
.line initcode.S:1 ).
The process needs physical memory in which to store this
program, the program needs to be copied to that memory,
and the process needs a page table that refers to
that memory.
.PP
.code userinit
calls 
.code setupkvm
.line vm.c:/^setupkvm/
to create a page table for the process with (at first) mappings
only for memory that the kernel uses.
It then calls
.code allocuvm
in order to allocate physical memory for the process and
add mappings for it to the process's page table.
.code allocuvm
.line vm.c:/^allocuvm/
calls
.code walkpgdir
to find whether each page in the required range of
virtual addresses is already mapped in the process's
page table.
If it isn't,
.code allocuvm
allocates a page of physical memory with
.code kalloc
and calls
.code mappages
to map the virtual address to the physical address of the allocated page.
.PP
The initial contents of the first process's memory are
the compiled form of
.code initcode.S ;
as part of the kernel build process, the linker
embeds that binary in the kernel and
defines two special symbols
.code _binary_initcode_start
and
.code _binary_initcode_size
telling the location and size of the binary
(XXX sidebar about why it is extern char[]).
.code Userinit
copies that binary into the new process's memory
by calling
.code inituvm ,
which uses
.code walkpgdir
to find the physical address of each of the process's
pages and copies successive pages of the binary there
.line vm.c:/^inituvm/ .
.code userinit
zeros the rest of the process's memory.
Then it sets up the trap frame with the initial user mode state:
the
.code cs
register contains a segment selector for the
.code SEG_UCODE
segment running at privilege level
.code DPL_USER
(i.e., user mode not kernel mode),
and similarly
.code ds ,
.code es ,
and
.code ss
use
.code SEG_UDATA
with privilege
.code DPL_USER .
The
.code eflags
.code FL_IF
is set to allow hardware interrupts;
we will reexamine this in Chapter \*[CH:TRAP].
The stack pointer 
.code esp
is the process's largest valid virtual address,
.code p->sz .
The instruction pointer is the entry point
for the initcode, address 0.
Note that
.code initcode
is not an ELF binary and has no ELF header.
It is just a small headerless binary that expects
to run at address 0,
just as the boot sector is a small headerless binary
that expects to run at address
.code 0x7c00 .
.code Userinit
sets
.code p->name
to
.code "initcode"
mainly for debugging.
Setting
.code p->cwd
sets the process's current working directory;
we will examine
.code namei
in detail in Chapter \*[CH:FSDATA].
.\" TODO: double-check: is it FSDATA or FSCALL?  namei might move.
.PP
Once the process is initialized,
.code userinit
marks it available for scheduling by setting 
.code p->state
to
.code RUNNABLE .
.\"
.section "Code: Running a process
.\"
Now that the first process's state is prepared,
it is time to run it.
After 
.code main
calls
.code userinit ,
.code mpmain
calls
.code scheduler
to start running user processes
.line main.c:/scheduler/ .
.code Scheduler
.line proc.c:/^scheduler/
looks for a process with
.code p->state
set to
.code RUNNABLE ,
and there's only one it can find:
.code initproc .
It sets the per-cpu variable
.code proc
to the process it found and calls
.code switchuvm
to tell the hardware to start using the target
process's page table
.line vm.c:/lcr3.*p..pgdir/ .
Changing page tables while executing in the kernel
works because 
.code setupkvm
causes all processes' page tables to have identical
mappings for kernel code and data.
.code switchuvm
also creates a new task state segment
.code SEG_TSS
that instructs the hardware to handle
an interrupt by returning to kernel mode
with
.code ss
and
.code esp
set to
.code SEG_KDATA<<3
and
.code (uint)proc->kstack+KSTACKSIZE ,
the top of this process's kernel stack.
We will reexamine the task state segment in Chapter \*[CH:TRAP].
.PP
.code scheduler
now sets
.code p->state
to
.code RUNNING
and calls
.code swtch
.line swtch.S:/^swtch/ 
to perform a context switch to the target process.
.code swtch 
saves the current registers and loads the saved registers
of the target process
.code proc->context ) (
into the x86 hardware registers,
including the stack pointer and instruction pointer.
The current context is not a process but rather a special
per-cpu scheduler context, so
.code scheduler
tells
.code swtch
to save the current hardware registers in per-cpu storage
.code cpu->scheduler ) (
rather than in any process's context.
We'll examine
.code switch
in more detail in Chapter \*[CH:SCHED].
The final
.code ret
instruction 
.line swtch.S:/ret$/
pops a new
.code eip
from the stack, finishing the context switch.
Now the processor is running process
.code p .
.PP
.code Allocproc
set
.code initproc 's
.code p->context->eip
to
.code forkret ,
so the 
.code ret
starts executing
.code forkret .
.code Forkret
.line proc.c:/^forkret/
releases the 
.code ptable.lock
(see Chapter \*[CH:LOCK])
and then returns.
.code Allocproc
arranged that the top word on the stack after
.code p->context
is popped off
would be 
.code trapret ,
so now 
.code trapret
begins executing,
with 
.code %esp
set to
.code p->tf .
.code Trapret
.line trapasm.S:/^trapret/ 
uses pop instructions to walk
up the trap frame just as 
.code swtch
did with the kernel context:
.code popal
restores the general registers,
then the
.code popl 
instructions restore
.code %gs ,
.code %fs ,
.code %es ,
and
.code %ds .
The 
.code addl
skips over the two fields
.code trapno
and
.code errcode .
Finally, the
.code iret
instructions pops 
.code %cs ,
.code %eip ,
and
.code %eflags
off the stack.
The contents of the trap frame
have been transferred to the CPU state,
so the processor continues at the
.code %eip
specified in the trap frame.
For
.code initproc ,
that means virtual address zero,
the first instruction of
.code initcode.S .
.PP
At this point,
.code %eip
holds zero and
.code %esp
holds 4096.
These are virtual addresses in the process's user address space.
The processor's paging hardware translates them into physical addresses
(we'll ignore segments since xv6 sets them up with the identity mapping
.line vm.c:/^ksegment/ ).
.code allocuvm
set up the PTE for the page at virtual address zero to
point to the physical memory allocated for this process,
and marked that PTE with
.code PTE_U
so that the user process can use it.
No other PTEs in the process's page table have the
.code PTE_U
bit set.
The fact that
.code userinit
.line proc.c:/UCODE/
set up the low bits of
.register cs
to run the process's user code at CPL=3 means that the user code
can only use PTE entries with
.code PTE_U
set, and cannot modify sensitive hardware registers such as
.register cr3 .
So the process is constrained to using only its own memory.
.PP
.code Initcode.S
.line initcode.S:/^start/
begins by pushing three values
on the stack—\c
.code $argv ,
.code $init ,
and
.code $0 —\c
and then sets
.code %eax
to
.code $SYS_exec
and executes
.code int
.code $T_SYSCALL :
it is asking the kernel to run the
.code exec
system call.
If all goes well,
.code exec
never returns: it starts running the program 
named by
.code $init ,
which is a pointer to
the NUL-terminated string
.code "/init"
.line initcode.S:/init.0/,/init.0/ .
If the
.code exec
fails and does return,
initcode
loops calling the
.code exit
system call, which definitely
should not return
.line initcode.S:/for.*exit/,/jmp.exit/ .
.PP
The arguments to the
.code exec
system call are
.code $init
and
.code $argv .
The final zero makes this hand-written system call look like the
ordinary system calls, as we will see in Chapter \*[CH:TRAP].  As
before, this setup avoids special-casing the first process (in this
case, its first system call), and instead reuses code that xv6 must
provide for standard operation.
.PP
The next chapter examines how xv6 configures
the x86 hardware to handle the system call interrupt
caused by
.code int
.code $T_SYSCALL .
The rest of the book builds up enough of the process
management and file system implementation
to finally implement
.code exec
in Chapter \*[CH:EXEC].
.\"
.section "Real world"
.\"
.PP
Most operating systems have adopted the process
concept, and most processes look similar to xv6's.
A real operating system would find free
.code proc
structures with an explicit free list
in constant time instead of the linear-time search in
.code allocproc ;
xv6 uses the linear scan
(the first of many) for simplicity.
.PP
Like most operating systems, xv6 uses the paging hardware
for memory protection and mapping and mostly ignores
segmentation. Most operating systems make far more sophisticated
use of paging than xv6; for example, xv6 lacks demand
paging from disk, copy-on-write fork, shared memory,
and automatically extending stacks.
xv6 does use segments for the common trick of
implementing per-cpu variables such as
.code proc
that are at a fixed address but have different values
on different CPUs.
Implementations of per-CPU (or per-thread) storage on non-segment
architectures would dedicate a register to holding a pointer
to the per-CPU data area, but the x86 has so few general
registers that the extra effort required to use segmentation
is worthwhile.
.PP
xv6's address space layout is awkward.
The user stack is at a relatively low address and grows down,
which means it cannot grow very much.
User memory cannot grow beyond 640 kilobytes.
Most operating systems avoid both of these problems by
locating the kernel instructions and data at high
virtual addresses (e.g. starting at 0x80000000) and
putting the top of the user stack just beneath the
kernel. Then the user stack can grow down from high
addresses, user data (via
.code sbrk )
can grow up from low addresses, and there is hundreds of megabytes of
growth potential between them.
It is also potentially awkward for the kernel to map all of
physical memory into the virtual address space; for example
that would leave zero virtual address space for user mappings
on a 32-bit machine with 4 gigabytes of DRAM.
.PP
In the earliest days of operating systems,
each operating system was tailored to a specific
hardware configuration, so the amount of memory
could be a hard-wired constant.
As operating systems and machines became
commonplace, most developed a way to determine
the amount of memory in a system at boot time.
On the x86, there are at least three common algorithms:
the first is to probe the physical address space looking for
regions that behave like memory, preserving the values
written to them;
the second is to read the number of kilobytes of 
memory out of a known 16-bit location in the PC's non-volatile RAM;
and the third is to look in BIOS memory
for a memory layout table left as
part of the multiprocessor tables.
None of these is guaranteed to be reliable,
so modern x86 operating systems typically
augment one or more of them with complex
sanity checks and heuristics.
In the interest of simplicity, xv6 assumes
that the machine it runs on has at least 16 megabytes
of memory.
A real operating system would have to do a better job.
.PP
Memory allocation was a hot topic a long time ago, the basic problems being
efficient use of very limited memory and
preparing for unknown future requests.
See Knuth.  Today people care more about speed than
space-efficiency.  In addition, a more elaborate kernel
would likely allocate many different sizes of small blocks,
rather than (as in xv6) just 4096-byte blocks;
a real kernel
allocator would need to handle small allocations as well as large
ones.
.\"
.section "Exercises"
.\"
1. Set a breakpoint at swtch.  Single step through to forkret.
Set another breakpoint at forkret's ret.
Continue past the release.
Single step into trapret and then all the way to the iret.
Set a breakpoint at 0x1b:0 and continue.
Sure enough you end up at initcode.

2. Do the same thing except single step past the iret.
You don't end up at 0x1b:0.  What happened?
Explain it.
Peek ahead to the next chapter if necessary.
.ig
[[Intent here is to point out the clock interrupt,
so that students aren't confused by it trying
to see the return to user space.
But maybe the clock interrupt doesn't happen at the
first iret anymore.  Maybe it happens when the 
scheduler turns on interrupts.  That would be great;
if it's not true already we should make it so.]]
..

3. Look at real operating systems to see how they size memory.
