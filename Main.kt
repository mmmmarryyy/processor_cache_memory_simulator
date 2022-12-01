var tickCounter = 0
val cache_line_count = 64
val cache_way = 2 
val cache_offset_bits = 4 //log_2(cache_line_size) 
val cache_set_size = 32 //cache_line_count/cache_way 
val cache_set_bits = 5 //log_2(cache_set_size) 
val tag_bits = 10 

data class Cache_Line(
    var lru: Boolean,
    var valid: Boolean,
    var dirty: Boolean,
    var tag: UInt
)

class Cache {
    var cacheMissCounter = 0
    var cacheHitCounter = 0
    
    private val cache_lines = List(cache_line_count) { Cache_Line(lru = true, valid = false, dirty = false, tag = 0u) }

    fun read_data(address: Int, bytes: Int) {
        val address = address.toUInt()
        val offset = address.shl(32 - cache_offset_bits).shr(32 - cache_offset_bits) //last cache_offset_bits bits
        val set = address.shr(cache_offset_bits).shl(32 - cache_set_bits).shr(32 - cache_set_bits) //last cache_set_bits bits
        val tag = address.shr(cache_offset_bits + cache_set_bits).shl(32 - tag_bits).shr(32 - tag_bits) //last tag_bits bits

        val left = set.toInt() * cache_way
        val right = (set.toInt()+1) * cache_way - 1

        for (i in left..right) {
            if (cache_lines[i].tag == tag) {
                cache_lines[i].lru = false
                cache_lines[i xor 1].lru = true

                if (cache_lines[i].valid) {
                    // нашли в кэше
                    tickCounter += 6 //время, через которое в результате кэш попадания, кэш начинает отвечать
                    tickCounter += 1 //отправка данных по шине d1
                    cacheHitCounter += 1

                    return
                }
            }
        }

        cache_miss(set, tag)

        tickCounter += 1 //отправка данных по шине d1
    }

    fun write_data(address: Int, bytes: Int) {
        val address = address.toUInt()
        val offset = address.shl(32 - cache_offset_bits).shr(32 - cache_offset_bits) //last cache_offset_bits bits
        val set = address.shr(cache_offset_bits).shl(32 - cache_set_bits).shr(32 - cache_set_bits) //last cache_set_bits bits
        val tag = address.shr(cache_offset_bits + cache_set_bits).shl(32 - tag_bits).shr(32 - tag_bits) //last tag_bits bits

        val left = set.toInt() * cache_way
        val right = (set.toInt()+1) * cache_way - 1

        for (i in left..right) {
            if (cache_lines[i].tag == tag) {
                if (cache_lines[i].valid) {
                    // нашли в кэше
                    tickCounter += 6 // время, через которое в результате кэш попадания, кэш начинает отвечать
                    cacheHitCounter += 1

                    cache_lines[i].lru = false 
                    cache_lines[i xor 1].lru = true

                    cache_lines[i].dirty = true

                    return
                }
            }
        }

        for (i in left..right) {
            if (cache_lines[i].lru) {
                cache_lines[i].dirty = true
            }
        }

        cache_miss(set, tag)
    }

    private fun cache_miss(set: UInt, tag: UInt) {
        tickCounter += 4 // время, через которое в результате кэш промаха, кэш посылает запрос к памяти.
        tickCounter += 100 // MemCTR обработка

        cacheMissCounter += 1

        val left = set.toInt() * cache_way
        val right = (set.toInt()+1) * cache_way - 1

        for (i in left..right) {
            if (cache_lines[i].lru) {
                cache_lines[i].valid = true

                if (cache_lines[i].dirty) {
                    tickCounter += 100
                }

                cache_lines[i].dirty = false
                cache_lines[i].tag = tag

                cache_lines[i].lru = false
                cache_lines[i xor 1].lru = true

                return
            }
        }
    }
}

fun main() {
    val cache = Cache()
    //Сложение, инициализация переменных и переход на новую итерацию цикла, выход из функции занимают 1 такт.
    // Умножение – 5 тактов. Обращение к памяти вида pc[x] считается за одну команду.
    val M = 64
    val N = 60
    val K = 32

    var pa = 0 //указатель на массив a
    tickCounter += 1 //инициализация

    val b = M * K //адрес начала массива b

    var pc = b + K * N * 2 //указатель на массив с
    tickCounter += 1 //инициализация

    repeat(M) {
        repeat(N) { x ->
            var pb = b //указатель на массив b
            tickCounter += 1 //инициализация
            tickCounter += 1 //инициализация переменной s

            repeat(K) { k ->
                cache.read_data(pa + k, 8/8)

                cache.read_data(pb + x * 2, 16/8)

                tickCounter += 5 //умножение
                tickCounter += 1 //сложение

                pb += N * 2
                tickCounter += 1 //сложение
                tickCounter += 1 //итерация цикла
            }

            cache.write_data(pc + x * 4, 32/8)
            tickCounter += 1 //итерация цикла
        }

        pa += K
        tickCounter += 1 //сложение

        pc += N * 4
        tickCounter += 1 //сложение
        tickCounter += 1 //итерация цикла
    }

    tickCounter += 1 //выход из функции

    println("Total ticks: $tickCounter")
    println("Total accesses: ${cache.cacheMissCounter + cache.cacheHitCounter}")
    println("Cache hits: ${cache.cacheHitCounter}")
    println("Cache misses: ${cache.cacheMissCounter}")
    println("Part of hits: ${cache.cacheHitCounter.toDouble() / (cache.cacheMissCounter + cache.cacheHitCounter)}")
}