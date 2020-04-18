/*
 * __strspn_aarch64_sve2 - compute the length of a string including
 * only characters within accept.
 *
 * Copyright (c) 2020, Arm Limited.
 * SPDX-License-Identifier: MIT
 */

#if __ARM_FEATURE_SVE2
/* Assumptions:
 *
 * ARMv8-a, AArch64
 * SVE2 Available.
 */

	.arch	armv8-a+sve2
	.text

	.globl	__strspn_aarch64_sve2
	.type	__strspn_aarch64_sve2, %function
	.p2align 4
__strspn_aarch64_sve2:
	setffr				/* initialize FFR */
	ptrue	p3.b			/* all ones; function invariant */
	mov	x2, x0			/* move input string out of the way */

	/* Read a vector's worth of bytes from accept,
           stopping on first fault.  */
	ldff1b	z1.b, p3/z, [x1]
	rdffrs	p1.b, p3/z
	b.nlast	.L_accept_fault

	/* First fault did not fail: the whole vector is valid.
	   Avoid depending on the contents of FFR beyond the branch.
	   See if we have the entire accept string in the vector. */
	cmpeq	p0.b, p3/z, z1.b, 0
	b.none	.L_accept_full

	/* EOS found.  Select the bytes before EOS and count them.
	   If the accept string is empty, the result is 0.  */
.L_accept_cont:
	brkb	p0.b, p3/z, p0.b
	cntp	x0, p3, p0.b
	cbz	x0, .L_ret

	/* Set all vector chars beyond EOS to a copy of the first char.
	   This makes sure that we don't get spurious nmatch hits.  */
	dup	z0.b, z1.b[0]
	sel	z1.b, p0, z1.b, z0.b
	cmp	x0, #16
	b.hi	.L_accept_gt16

	/*
	 * The accept string fits within one vector segment.
	 */
	dup	z1.q, z1.q[0]		/* replicate segment to all */
	mov	x0, 0

	/* Main loop with strlen(accept) <= 16. */
	.p2align 4
.L_one_segment_loop:
	ldff1b	z0.b, p3/z, [x2, x0]
	rdffrs	p0.b, p3/z
	b.nlast	.L_one_segment_fault
	nmatch	p1.b, p3/z, z0.b, z1.b
	incb	x0, all			/* speculate increment */
	b.none	.L_one_segment_loop

	/* Non-accepted character found. */
	decb	x0, all			/* undo speculate */
.L_one_segment_end:
	brkb	p1.b, p3/z, p1.b	/* select bytes before first */
	incp	x0, p1.b		/* count them */
.L_ret:
	ret

	/* First fault failed: only some of the vector is valid.
	   Perform the comparison only on the valid bytes.  */
.L_one_segment_fault:
	nmatch	p1.b, p0/z, z0.b, z1.b
	b.any	.L_one_segment_end

	/* All chars matched.  Re-init FFR, increment, and loop.  */
	setffr
	incp	x0, p0.b
	b	.L_one_segment_loop

.L_accept_gt16:
	cmp	x0, #32
	b.hi	.L_accept_large

	/*
	 * The accept string fits within two vector segments.
	 */
	dup	z2.q, z1.q[1]		/* replicate segments */
	dup	z1.q, z1.q[0]
	mov	x0, 0

	/* Main loop with strlen(accept) <= 32 */
	.p2align 4
.L_two_segment_loop:
	ldff1b	z0.b, p3/z, [x2, x0]
	rdffrs	p0.b, p3/z
	b.nlast	.L_two_segment_fault
	match	p1.b, p3/z, z0.b, z1.b
	match	p2.b, p3/z, z0.b, z2.b
	incb	x0, all			/* speculate increment */
	nors	p1.b, p3/z, p1.b, p2.b
	b.none	.L_two_segment_loop

	/* Non-accepted character found. */
	decb	x0, all			/* undo speculate */
.L_two_segment_end:
	brkb	p1.b, p3/z, p1.b	/* select bytes before first */
	incp	x0, p1.b		/* count them */
	ret

	/* First fault failed: only some of the vector is valid.
	   Perform the comparison only on the valid bytes.  */
.L_two_segment_fault:
	match	p1.b, p0/z, z0.b, z1.b
	match	p2.b, p0/z, z0.b, z2.b
	nors	p1.b, p0/z, p1.b, p2.b
	b.any	.L_two_segment_end

	/* All chars matched.  Re-init FFR, increment, and loop.  */
	setffr
	incp	x0, p0.b
	b	.L_two_segment_loop

.L_accept_fault:
	/* We did not manage to read the first vector of accept.
	   Check for EOS in what we did read.  */
	cmpeq	p0.b, p1/z, z1.b, #0
	b.any	.L_accept_cont

	/* Try once more, assuming that the implementation of
	   first-fault doesn't like crossing pages.  If we still
	   get a fault, fall back to integer code.  */
	cntp	x0, p3, p1.b
	setffr
	ldff1b	z0.b, p3/z, [x1, x0]
	rdffrs	p0.b, p3/z
	b.nlast	.L_accept_large

	/* Splice the two vectors together and again look for EOS.  */
	splice	z1.b, p1, z1.b, z0.b
	cmpeq	p0.b, p3/z, z1.b, 0
	b.any	.L_accept_cont

	/* We haven't managed to load the whole accept string in one vector.
	   Fall through to maybe try loading more.  */

.L_accept_full:
	/* We didn't find the end of accept in the first VL.
	   Quick check to see if we're prepared to handle more.  */
	cntb	x0, all
	cmp	x0, #32
	b.hi	.L_accept_large

	/* This means VL == 16.  Load the next vector worth. */
	ldff1b	z2.b, p3/z, [x1, x0]
	rdffrs	p2.b, p3/z
	b.nlast 2f

	cmpeq	p2.b, p3/z, z2.b, 0
	b.none	.L_accept_large

1:	brkb	p0.b, p3/z, p1.b
	dup	z0.b, z2.b[0]
	sel	z2.b, p0, z2.b, z0.b
	mov	x0, 0
	b	.L_two_segment_loop

2:	cmpeq	p1.b, p2/z, z2.b, 0
	b.any	1b

	/* We haven't managed to load the whole string.
	   Fall back to integer code.  */

.L_accept_large:
	/*
	 * TODO: How many NMATCH insns is it worth combining?
	 * Beyond 255 characters, it is obvious that the user is punking us
	 * with duplicates in the set.  Beyond 128 characters (8 segments),
	 * it would be quicker to compare against the inverted set.
	 *
	 * For now, let us consider these cases vanishingly rare.
	 * Fall back to integer code.
	 */
	mov	x0, x2
	b	strspn

	.size	__strspn_aarch64_sve2, . - __strspn_aarch64_sve2
#endif
