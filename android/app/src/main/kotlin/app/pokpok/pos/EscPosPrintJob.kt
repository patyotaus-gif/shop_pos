package app.pokpok.pos

import java.io.OutputStream

/** Only the bounded raster stream produced by Pokpok, not arbitrary ESC/POS. */
internal class EscPosPrintJob private constructor(
    private val data: ByteArray,
    private val bands: List<Band>
) {
    private data class Band(val start: Int, val size: Int, val rows: Int)

    fun send(output: OutputStream, beforeWrite: () -> Unit, pause: (Long) -> Unit) {
        fun write(start: Int, length: Int) {
            var offset = start
            while (offset < start + length) {
                val count = minOf(512, start + length - offset)
                beforeWrite()
                output.write(data, offset, count)
                output.flush()
                offset += count
                pause(10)
            }
        }
        write(0, 2)
        for (band in bands) {
            write(band.start, band.size)
            // Pace by printed rows as well as radio bytes. flush() is not an
            // acknowledgement that the printer has consumed its receive buffer.
            pause(band.rows * 3L)
        }
        write(data.size - 3, 3)
        // Keep RFCOMM alive while the final raster/feed drains. This is a
        // conservative delay, NOT confirmation of physical paper output.
        pause(2_000)
    }

    companion object {
        fun parse(data: ByteArray): EscPosPrintJob {
            fun byte(index: Int) = data[index].toInt() and 255
            require(data.size in 14..2_000_000)
            require(byte(0) == 0x1b && byte(1) == 0x40)
            val end = data.size - 3
            require(byte(end) == 0x1b && byte(end + 1) == 0x4a && byte(end + 2) == 120)
            var offset = 2
            var totalRows = 0
            var rowBytes = 0
            val bands = mutableListOf<Band>()
            while (offset < end) {
                require(end - offset >= 8)
                require(byte(offset) == 0x1d && byte(offset + 1) == 0x76 &&
                    byte(offset + 2) == 0x30 && byte(offset + 3) == 0)
                val width = byte(offset + 4) + byte(offset + 5) * 256
                val rows = byte(offset + 6) + byte(offset + 7) * 256
                require(width == 48 || width == 72)
                require(rowBytes == 0 || rowBytes == width)
                rowBytes = width
                require(rows in 1..64)
                totalRows += rows
                require(totalRows <= 12_000)
                val size = 8 + width * rows
                require(size <= end - offset)
                bands.add(Band(offset, size, rows))
                offset += size
            }
            require(offset == end && bands.isNotEmpty())
            return EscPosPrintJob(data, bands)
        }
    }
}
