// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice Enables public storage access for efficient state retrieval by external contracts.
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Extsload /* is IExtsload */ {
    /*
     * ── SOLIDITY MEMORY LAYOUT ──────────────────────────────────────────
     *
     * EVM memory is temporary and byte-addressed. It exists only during
     * the current call; unlike storage, it is not preserved between calls.
     *
     * Solidity reserves these memory regions:
     *
     * Address range       Purpose
     * 0x00 - 0x3F         Scratch space (64 bytes)
     * 0x40 - 0x5F         Free memory pointer (32 bytes)
     * 0x60 - 0x7F         Zero slot (32 bytes)
     * 0x80 onwards        General-purpose memory
     *
     *
     * ── 1. SCRATCH SPACE: 0x00 - 0x3F ──────────────────────────────────
     *
     * This is the first 64 bytes of memory.
     * Solidity uses this region as temporary working space.
     * It can be used by inline assembly for temporary values.
     *
     * Example:
     *
     * mstore(0, 100)
     * This writes 100 into memory starting at address 0.
     * It occupies bytes 0 through 31.
     * 
     * mstore(0x20, 200)
     * This writes 200 into memory starting at address 0x20.
     * It occupies bytes 32 through 63.
     *
     * Both writes fit inside the 64-byte scratch space.
     *
     * The first Extsload function uses this region because it only needs
     * to return one bytes32 value (32 bytes). It writes that value at
     * offset 0 and immediately returns those 32 bytes.
     *
     *
     * ── 2. FREE MEMORY POINTER: 0x40 - 0x5F ────────────────────────────
     *
     * Solidity stores the free memory pointer in the 32-byte word
     * beginning at memory address 0x40.
     *
     * The pointer's VALUE tells Solidity where the next general-purpose
     * memory allocation can begin. It normally starts at 0x80 because
     * the first 128 bytes are reserved for the memory conventions above.
     *
     * IMPORTANT: 0x40 is where the pointer is stored; it is not usually
     * the address where the next memory allocation begins.
     *
     * Example:
     *
     * Assume memory at 0x40 contains 0x80.
     *
     * let memptr := mload(0x40)
     *
     * MLOAD reads the 32-byte word at address 0x40. Its contents are
     * 0x80, so memptr receives 0x80.
     *
     * In other words:
     * - 0x40 = address where the pointer is stored.
     * - 0x80 = The pointer; it points to the next available memory address.
     *
     * Example of allocating 96 bytes:
     *
     * Starting address = 0x80.
     * Size              = 0x60 (96 bytes).
     * Used addresses    = 0x80-0xDF.
     * Next free address = 0xE0.
     *
     * Solidity would update the pointer with:
     *
     * mstore(0x40, 0xE0)
     *
     * A later mload(0x40) would then return 0xE0.
     *
     *
     * ── 3. ZERO SLOT: 0x60 - 0x7F ──────────────────────────────────────
     *
     * Solidity reserves this 32-byte word as the zero slot. It is
     * expected to remain zero and is used as the default memory
     * reference for uninitialized dynamic memory arrays.
     *
     * A dynamic memory array is represented by a pointer to a word
     * containing its length. Its elements follow that length word.
     *
     * Example of an allocated array:
     *
     * uint256[] memory numbers = new uint256[](3);
     *
     * Address     Content
     * 0x80        3              Array length
     * 0xA0        First element
     * 0xC0        Second element
     * 0xE0        Third element
     *
     * The array reference points to 0x80, where its length is stored.
     *
     * An uninitialized dynamic memory array uses the zero slot as its
     * default reference. Because mload(0x60) is expected to be zero,
     * that reference represents an array whose length is zero.
     *
     * Why must we avoid writing to 0x60?
     *
     * If assembly executes mstore(0x60, 3), the zero slot no longer
     * contains zero. An uninitialized array using that default reference
     * could then appear to have length 3. This corrupts Solidity's
     * expected zero-slot representation.
     *
     *
     * ── 4. GENERAL-PURPOSE MEMORY: 0x80 ONWARDS ────────────────────────
     *
     * Solidity normally allocates memory objects here, including
     * dynamic arrays, strings, bytes, and memory structs.
     *
     * The batch Extsload functions use this region to construct their
     * ABI-encoded return data.
     *
     *
     * ── READ ONE STORAGE SLOT ──────────────────────────────────────────
     *
     * This function reads one storage slot and returns its bytes32 value.
     */
       // /// @inheritdoc IExtsload
    function extsload(bytes32 slot) external view returns (bytes32) {
        assembly ("memory-safe") {
            /*
             * SLOAD reads the 32-byte value stored at the supplied slot.
             *
             * Example: if storage slot 5 contains 100, sload(5) returns
             * that value (i.e, 100).
             *
             * The return type is bytes32, a fixed-size value of 32 bytes.
             *
             * Memory is byte-addressed, so writing at offset 0
             * occupies bytes 0 through 31.
             *
             * This is enough space for the entire return value.
             *
             * Unlike a dynamic array, bytes32 does not require:
             * - An ABI offset.
             * - A length word.
             *
             * We can therefore write the value at memory offset 0
             * and immediately return those 32 bytes.
             * 
             */
            mstore(0, sload(slot))

            /*
             * RETURN takes two arguments:
             *
             * First argument: starting memory offset.
             * Second argument: number of bytes to return or simply byte length.
             *
             * return(0, 0x20):
             * Start at memory offset 0.
             * Return 0x20 = 32 bytes.
             *
             * this returns 32 bytes beginning at memory offset 0.
             *
             * RETURN ends this EVM execution and sends the selected memory
             * bytes back to the caller as returndata.
             */
            return(0, 0x20)
        }
    }

    /*
     * ── READ CONSECUTIVE STORAGE SLOTS ─────────────────────────────────
     *
     * This function reads nSlots consecutive storage slots, beginning
     * at startSlot, and returns their values as a dynamic bytes32 array.
     *
     * and each return value of the dynamic array contains:
     *
     * 1. Offset to the dynamic array data.
     * 2. Array length.
     * 3. Array elements.
     *
     */
    function extsload(bytes32 startSlot, uint256 nSlots)
        external
        view
        returns (bytes32[] memory)
    {
        assembly ("memory-safe") {
            /*
             * GET THE STARTING MEMORY ADDRESS
             *
             * mload(0x40) reads the free memory pointer stored at 0x40.
             * For this example, assume it contains 0x80.
             */
            let memptr := mload(0x40)

            /*
             * SAVE THE ORIGINAL MEMORY ADDRESS
             *
             * We preserve the starting address because memptr
             * will advance as we construct the return array.
             *
             * Example:
             * start = 0x80.
             *
             * Even when memptr later becomes 0xC0 or 0xE0,
             * start remains 0x80.
             */
            let start := memptr

            /*
             * CALCULATE THE MEMORY SIZE OF THE ARRAY ELEMENTS
             *
             * SHL shifts bits to the left.
             * Shifting left by 5 is equivalent to multiplying by 2^5.
             *
             * 2^5 = 32.
             *
             * Therefore:
             * shl(5, nSlots) = nSlots * 32.
             *
             * Example:
             * nSlots = 3.
             * 3 x 32 = 96 bytes = 0x60.
             *
             * Also in binary representation:
             * 3 = 00000011
             *
             * Shift left by 5:
             *     01100000
             *
             * Result:
             * 96 bytes = 0x60.
             *
             * This is to calculate the space occupied by the slots.
             * this is to say if the number of slots is 3, then the total size of
             * the array elements in memory will be 3 * 32 = 96 bytes.
             */
            let length := shl(5, nSlots)

            /*
             * WRITE THE ABI OFFSET
             *
             * Because the function returns a dynamic array, its ABI-encoded
             * return data begins with an offset word.
             *
             * This offset tells the ABI decoder where to find the array's
             * length word, relative to the beginning of the encoded return data.
             *
             * We begin writing the encoded return data at `start`.
             *
             * The layout is:
             *
             *   start + 0 bytes:  Offset (0x20 = 32)
             *   start + 32 bytes: Array length
             *   start + 64 bytes: First array element
             *
             * We write 0x20 because the array's length word is located
             * 32 bytes after the beginning of the encoded return data.
             *
             * Example when start = 128:
             *
             *   Memory address 128: Offset value (32)
             *   Memory address 160: Array length
             *   Memory address 192: First array element
             *
             * The decoder reads the offset (32), adds it to the beginning
             * of the encoded return data (128), and reaches address 160.
             *
            */
            mstore(memptr, 0x20)

            /*
             * WRITE THE ARRAY LENGTH
             *
             * The next 32-byte word stores the number of elements.
             *
             * Example:
             * If nSlots = 3, this writes 3.
             */
            mstore(add(memptr, 0x20), nSlots)

            /*
             * MOVE THE MEMORY POINTER PAST THE ABI HEADER
             *
             * The ABI header consists of two 32-byte words:
             *
             * 1. Offset: 32 bytes.
             * 2. Array length: 32 bytes.
             *
             * Total header size = 64 bytes.
             *
             * We advance memptr by 64 bytes so that it points
             * to the beginning of the array elements.
             *
             * Example:
             * Before: memptr = 128.
             * After:  memptr = 192.
             *
             * The first array element will be written at address 192.
            */
            memptr := add(memptr, 0x40)

            /*
             * CALCULATE THE END ADDRESS
             *
             * Add `length` to `memptr` to calculate the address
             * immediately after the last array element.
             *
             * Example:
             *
             * memptr = 0xC0 (192): beginning of the array elements.
             * length = 0x60 (96): space required for three elements.
             *
             * end = 0xC0 + 0x60
             * end = 0x120 (288).
             *
             * Memory layout:
             *
             * 0xC0–0xDF: First element (32 bytes).
             * 0xE0–0xFF: Second element (32 bytes).
             * 0x100–0x11F: Third element (32 bytes).
             *
             * 0x120 is the first address after the array.
             *
             * We use this address as the stopping point for the loop.
            */
            let end := add(memptr, length)

            /*
             * LOOP THROUGH CONSECUTIVE STORAGE SLOTS
             *
             * for {} 1 {} means:
             *
             * Initialization: empty.
             * Condition: 1 (always true).
             * Post-expression: empty.
             *
             * The loop continues until BREAK is executed.
             */
            for {} 1 {} {
                /*
                 * Read the current storage slot and write its value
                 * into the current output-memory position.
                 *
                 * Example: if startSlot is 5 and slot 5 contains 100,
                 * this writes 100 at the current memptr.
                 */
                mstore(memptr, sload(startSlot))

                /*
                 * Each bytes32 element occupies 32 bytes.
                 * Move forward by 32 bytes for the next bytes32 element.
                 */
                memptr := add(memptr, 0x20)

                /*
                 * Move to the next consecutive storage slot.
                 * For example: 5 becomes 6, then 7.
                 */
                startSlot := add(startSlot, 1)

                /*
                 * CHECK WHETHER WE HAVE REACHED THE END
                 *
                 * `lt(memptr, end)` checks whether the current memory pointer
                 * is still smaller than the end address.
                 *
                 * It returns:
                 * - 1 if memptr < end.
                 * - 0 if memptr >= end.
                 *
                 * `iszero()` reverses this result:
                 * - iszero(1) = 0: condition is false, so the loop continues.
                 * - iszero(0) = 1: condition is true, so BREAK executes.
                 *
                 * Example:
                 *
                 * If memptr = 192 and end = 288:
                 * - lt(192, 288) returns 1.
                 * - iszero(1) returns 0.
                 * - The loop continues.
                 *
                 * If memptr = 288 and end = 288:
                 * - lt(288, 288) returns 0.
                 * - iszero(0) returns 1.
                 * - BREAK executes.
                 *
                 * We exit when memptr reaches or passes end.
                */
                if iszero(lt(memptr, end)) { break }
            }
            /*
            * RETURN THE COMPLETE ABI-ENCODED ARRAY
            *
            * `start` stores the original memory address where we began
            * building the ABI-encoded return data.
            *
            * `end` stores the address immediately after the final array element.
            *
            * We subtract `start` from `end` to calculate the total number
            * of bytes occupied by the complete encoded return data.
            *
            * Example:
            *
            * start = 0x80 (128).
            * end   = 0x120 (288).
            *
            * Total size = end - start = 160 bytes (0xA0).
            *
            * These 160 bytes contain:
            * - 32 bytes for the ABI offset.
            * - 32 bytes for the array length.
            * - 96 bytes for three array elements.
            *
            * `return(offset, size)` is an EVM instruction that returns
            * the specified memory region to the caller and terminates
            * the current execution.
            *
            * We return from `start` for `end - start` bytes so that
            * the caller receives the complete ABI-encoded array.
            *
            * Since RETURN terminates execution, we do not need to update
            * the free memory pointer for subsequent Solidity allocations.
            */
            return(start, sub(end, start))
        }
    }

    /*
     * ── READ SPECIFIC STORAGE SLOTS ────────────────────────────────────
     *
     * Unlike the previous function, this one does not assume that the
     * requested slots are consecutive. The caller supplies an array of
     * slot numbers in calldata, and the function reads each one.
     */
    function extsload(bytes32[] calldata slots)
        external
        view
        returns (bytes32[] memory)
    {
        assembly ("memory-safe") {
            /*
             * START BUILDING THE RETURN ARRAY
             *
             * Read the free memory pointer and preserve its initial value.
             */
            let memptr := mload(0x40)
            let start := memptr

            /*
             * WRITE THE ABI HEADER
             *
             * The return value is one dynamic array, so its ABI encoding
             * begins with an offset word (0x20), followed by the array
             * length.
             */
            mstore(memptr, 0x20)

            /*
             * WRITE THE ARRAY LENGTH
             *
             * slots.length gives the number of elements
             * supplied in the calldata array.
             */
            mstore(add(memptr, 0x20), slots.length)

            /*
             * Move past the offset and length words to the first output
             * element. Each word is 32 bytes, so the header is 0x40 bytes.
             */
            memptr := add(memptr, 0x40)

            /*
             * Calculate the address immediately after the output array.
             * Each requested slot produces one 32-byte output element.
             */
            let end := add(memptr, shl(5, slots.length))

            /*
            * FIND THE INPUT ARRAY IN CALLDATA
            *
            * `slots` is a dynamic array supplied by the caller and declared as `calldata`.
            *
            * `slots.offset` gives the calldata byte position where the first bytes32 element begins.
            *
            * We assign this position to `calldataptr` so we can read
            * each supplied storage slot number using CALLDATALOAD.
            *
            * Example:
            *
            * If the caller supplies [5, 12, 20], and the first element
            * begins at calldata position 68:
            *
            * calldataptr = 68.
            *
            * Each element occupies 32 bytes, so the next elements
            * are located at positions 100 and 132.
            *
            */
            let calldataptr := slots.offset

            for {} 1 {} {
                /*
                 * READ THE NEXT SLOT NUMBER FROM CALLDATA
                 *
                 * CALLDATALOAD reads 32 bytes beginning at calldataptr.
                 * That loaded value is used as the slot argument to SLOAD.
                 *
                 * Example:
                 * If the next calldata element is 5, then
                 * calldataload(calldataptr) returns 5, and sload(5)
                 * reads storage slot 5.
                 *
                 * The value read from storage is written to output memory.
                 */
                mstore(memptr, sload(calldataload(calldataptr)))

                /*
                 * Advance both pointers by one word:
                 * - memptr moves to the next output element.
                 * - calldataptr moves to the next requested slot number.
                 */
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)

                /*
                 * Stop after all requested slot numbers have been processed.
                 */
                if iszero(lt(memptr, end)) { break }
            }

            /*
             * Return the ABI header and all output elements.
             * As in the previous overload, RETURN ends this execution.
             */
            return(start, sub(end, start))
        }
    }


    /*
    * ── EXAMPLE: READING THREE CONSECUTIVE STORAGE SLOTS ───────────────
    *
    * Assume:
    *
    * - startSlot = 5
    * - nSlots = 3
    * - storage slot 5 contains 100
    * - storage slot 6 contains 200
    * - storage slot 7 contains 300
    * - the free memory pointer contains 0x80.
    *
    * We want to read three consecutive storage slots and return
    * their values as a bytes32[] array.
    *
    * FIRST: CALCULATE THE SPACE REQUIRED FOR THE ELEMENTS
    *
    * Each array element occupies 32 bytes.
    *
    * length = nSlots * 32
    * length = 3 * 32 = 96 bytes = 0x60.
    *
    * This is the space required for the three elements only.
    * It does not include the ABI header.
    *
    * SECOND: BUILD THE ABI HEADER
    *
    * The ABI header contains two 32-byte words:
    *
    * Address     Content     Meaning
    * 0x80        0x20        Offset to the array length
    * 0xA0        3           Number of array elements
    *
    * The first word tells the decoder that the array length
    * is located 32 bytes after the beginning of the encoded data.
    *
    * The second word stores the actual number of elements: 3.
    *
    * THIRD: FIND WHERE THE ARRAY ELEMENTS SHOULD BEGIN
    *
    * The ABI header occupies 64 bytes:
    * 32 bytes for the offset + 32 bytes for the array length.
    *
    * Therefore, we advance past the header:
    *
    * memptr = 0x80 + 0x40 = 0xC0.
    *
    * `memptr` now points to the first location where an array
    * element should be written.
    *
    * We calculate the address immediately after all three elements:
    *
    * end = 0xC0 + 0x60 = 0x120.
    *
    * `end` is the stopping address for our loop.
    *
    * FOURTH: READ THE STORAGE SLOTS AND WRITE THEIR VALUES TO MEMORY
    *
    * Iteration 1:
    *
    * - sload(5) reads the value stored at storage slot 5: 100.
    * - mstore(0xC0, 100) writes that value into memory.
    * - memptr advances by 32 bytes to 0xE0.
    * - startSlot advances to 6.
    *
    * Iteration 2:
    *
    * - sload(6) reads the value stored at storage slot 6: 200.
    * - mstore(0xE0, 200) writes that value into memory.
    * - memptr advances by 32 bytes to 0x100.
    * - startSlot advances to 7.
    *
    * Iteration 3:
    *
    * - sload(7) reads the value stored at storage slot 7: 300.
    * - mstore(0x100, 300) writes that value into memory.
    * - memptr advances by 32 bytes to 0x120.
    * - startSlot advances to 8.
    *
    * FIFTH: CHECK WHETHER THE LOOP SHOULD STOP
    *
    * Now:
    *
    * memptr = 0x120
    * end    = 0x120
    *
    * `lt(memptr, end)` returns 0 because memptr is not smaller
    * than end.
    *
    * `iszero(0)` returns 1, so BREAK executes and the loop exits.
    *
    * SIXTH: RETURN THE COMPLETE ABI-ENCODED DATA
    *
    * We return from the original starting address, 0x80,
    * for a total of 0xA0 bytes:
    *
    * end - start = 0x120 - 0x80 = 0xA0 (160 bytes).
    *
    * These 160 bytes contain:
    *
    * - 32 bytes: ABI offset.
    * - 32 bytes: array length.
    * - 96 bytes: three array elements.
    *
    * The caller's ABI decoder interprets this data and produces:
    *
    * [100, 200, 300]
    *
    *
    * NOTE ABOUT ZERO ELEMENTS
    *
    * What happens if nSlots = 0?
    *
    * length = 0 * 32 = 0.
    *
    * Therefore:
    *
    * end = memptr + 0 = memptr.
    *
    * However, our loop uses `for {} 1 {}`.
    * Its condition is always true, so it enters the loop body
    * at least once before checking whether it has reached the end.
    *
    * Consequently, it performs one SLOAD and writes one word
    * to memory, even though we requested zero elements.
    *
    * After advancing memptr by 32 bytes, the loop checks:
    *
    * memptr >= end
    *
    * This is true, so BREAK executes.
    *
    * The extra word is outside the returned data because
    * `end - start` still covers only the 64-byte ABI header.
    *
    * The caller therefore receives a valid empty array.
    *
    */
}