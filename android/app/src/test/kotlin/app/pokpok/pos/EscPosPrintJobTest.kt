package app.pokpok.pos

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import org.junit.Assert.*
import org.junit.Test

class EscPosPrintJobTest {
    private fun fixture(width: Int, rows: Int): ByteArray {
        val output = ByteArrayOutputStream()
        output.write(byteArrayOf(0x1b, 0x40))
        var top = 0
        while (top < rows) {
            val count = minOf(64, rows - top)
            output.write(byteArrayOf(0x1d, 0x76, 0x30, 0, width.toByte(), 0, count.toByte(), 0))
            // Includes ESC bytes inside raster pixels; the parser must skip
            // payload lengths rather than interpreting them as commands.
            output.write(ByteArray(width * count) { ((it + top) % 256).toByte() })
            top += count
        }
        output.write(byteArrayOf(0x1b, 0x4a, 120))
        return output.toByteArray()
    }

    @Test fun preservesLongReceiptAndFooterWithBoundedPacing() {
        for (width in listOf(48, 72)) {
            val input = fixture(width, 12_000)
            val output = ByteArrayOutputStream()
            val delays = mutableListOf<Long>()
            EscPosPrintJob.parse(input).send(output, {}, { delays.add(it) })
            assertArrayEquals(input, output.toByteArray())
            assertEquals(2_000L, delays.last())
            assertTrue(delays.contains(64 * 3L))
            // Leave time for 15-second connect within the 90-second watchdog.
            assertTrue(delays.sum() + 15_000 < 90_000)
        }
    }

    @Test fun rejectsIncompleteRasterAndUnsupportedCommandsBeforeWriting() {
        val input = fixture(48, 65)
        val incomplete = input.copyOfRange(0, input.size - 4) + byteArrayOf(0x1b, 0x4a, 120)
        val mixedWidth = input.clone().also { it[2 + 8 + 48 * 64 + 4] = 72 }
        val badHeader = input.clone().also { it[2] = 0x1b }
        for (invalid in listOf(incomplete, mixedWidth, badHeader, fixture(48, 12_001))) {
            assertThrows(IllegalArgumentException::class.java) { EscPosPrintJob.parse(invalid) }
        }
    }

    @Test fun partialWriteFailureDoesNotRetryOrAppendFeed() {
        var writes = 0
        val output = object : OutputStream() {
            override fun write(value: Int) { error("Expected bounded array writes") }
            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                writes++
                if (writes == 3) throw IOException("partial delivery")
            }
        }
        val delays = mutableListOf<Long>()
        assertThrows(IOException::class.java) {
            EscPosPrintJob.parse(fixture(48, 128)).send(output, {}, { delays.add(it) })
        }
        assertEquals(3, writes)
        assertFalse(delays.contains(2_000))
    }

    @Test fun cancellationStopsBeforeAnyAdditionalWrite() {
        val output = ByteArrayOutputStream()
        var checks = 0
        assertThrows(InterruptedException::class.java) {
            EscPosPrintJob.parse(fixture(48, 64)).send(output, {
                if (++checks == 2) throw InterruptedException()
            }, {})
        }
        assertArrayEquals(byteArrayOf(0x1b, 0x40), output.toByteArray())
    }
}
