//delay фиксит возможную гонку при чтении значения clk, придуман Артемом Пешковым и Тимофеем Маловым
`define delay(TIME, CLOCK) \
    for (int i = 0; i < TIME; i++) begin \
        wait(clk == (i + !CLOCK) % 2); \
    end

`define BYTE 8

`define C1_NOP 0 
`define C1_READ8 1 
`define C1_READ16 2 
`define C1_READ32 3 
`define C1_INVALIDATE_LINE 4 
`define C1_WRITE8 5 
`define C1_WRITE16 6 
`define C1_WRITE32_OR_RESPONSE 7 

`define C2_NOP 0 
`define C2_RESPONSE 1 
`define C2_READ_LINE 2 
`define C2_WRITE_LINE 3 

`define VALID 1
`define DIRTY 1

`define CACHE_WAY 2
`define CACHE_TAG_SIZE 10
`define SET_SIZE 5 
`define OFFSET_SIZE 4 

`define MEM_SIZE 524288 //2^19
`define CACHE_LINE_SIZE 16
`define CACHE_LINE_COUNT 64
`define CACHE_SETS_COUNT (`CACHE_LINE_COUNT / `CACHE_WAY)
`define CACHE_LINE_SIZE_IN_BITS (`CACHE_LINE_SIZE * `BYTE)
`define WHOLE_CACHE_LINE_SIZE_IN_BITS (`VALID + `DIRTY + `CACHE_TAG_SIZE + `CACHE_LINE_SIZE_IN_BITS)

`define MEMCTR_RESPONSE_TIME 100
`define CACHE_HIT_RESPONSE_TIME 6
`define CACHE_MIS_RESPONSE_TIME 4

`define MAX_POSSIBLE_SIZE_OF_REQUESTED_DATA 32
`define SEND_FROM_MEM (`CACHE_LINE_SIZE/`CACHE_WAY)

`define ADDR1_BUS_SIZE 15 
`define ADDR2_BUS_SIZE 15 

`define DATA1_BUS_SIZE 16
`define DATA2_BUS_SIZE 16

`define CTR1_BUS_SIZE 3
`define CTR2_BUS_SIZE 2

module test;
    reg clk = 0;

    wire [`ADDR1_BUS_SIZE-1:0] a1;
    wire [`DATA1_BUS_SIZE-1:0] d1;
    wire [`CTR1_BUS_SIZE-1:0] c1;
    wire [`ADDR2_BUS_SIZE-1:0] a2;
    wire [`DATA2_BUS_SIZE-1:0] d2;
    wire [`CTR2_BUS_SIZE-1:0] c2;

    reg c_dump = 0; 
    reg m_dump = 0;
    reg reset = 0; 

    integer mdump_file = 0;
    integer cdump_file = 0;
    integer log_file = 0;

    cpu test_cpu(clk, a1, d1, c1);
    cache test_cache(clk, a1, d1, c1, a2, d2, c2, c_dump, reset);
    memory test_memory(clk, a2, d2, c2, m_dump, reset);

    initial begin
        for (int i = 0; i < 14000000; i++) begin
            #1;
            clk = 1-clk; 
        end
    end
endmodule

module cpu(input clk, output wire [`ADDR1_BUS_SIZE-1 : 0] a1, inout wire [`DATA1_BUS_SIZE-1 : 0] d1, inout wire [`CTR1_BUS_SIZE-1 : 0] c1);
    reg [`ADDR1_BUS_SIZE -1:0] inner_a1 = 'z;
    reg [`DATA1_BUS_SIZE - 1 : 0] inner_d1 = 'z;
    reg [`CTR1_BUS_SIZE - 1 : 0] inner_c1 = 'z;

    assign a1 = inner_a1;
    assign d1 = inner_d1;
    assign c1 = inner_c1;

    reg [7:0] result_for_reading_8 = 'z;
    bit reading_8 = 0;

    reg [15:0] result_for_reading_16 = 'z;
    bit reading_16 = 0;

    reg [31:0] result_for_writing_32 = 'z;
    bit writing_32 = 0;

    //начало симуляции задачи
    int M = 64;
    int N = 60;
    int K = 32;

    int pa = 0;
    int b = M * K;
    int pb = 0;
    int pc = b + K * N * 2;

    int s = 0;
    int additional_tick_counter = 0;

    initial begin
        test.log_file = $fopen("log.txt", "w");

        task_simulation();

        $display("Total ticks: %0t", $time/2 + additional_tick_counter);
        $display("Total memory accesses: %0d", test.test_cache.cacheMissCounter + test.test_cache.cacheHitCounter);
        $display("Cache hits: %0d", test.test_cache.cacheHitCounter);
        $display("Cache misses: %0d", test.test_cache.cacheMissCounter);
        $display("Part of hits: %0f", test.test_cache.cacheHitCounter*1.0 / (test.test_cache.cacheMissCounter + test.test_cache.cacheHitCounter));

        test.reset = 1;

        `delay(2,1);
        
        $fclose(test.log_file);
    end

    always @(negedge clk) begin
        if (c1 == `C1_WRITE32_OR_RESPONSE) begin
            if (reading_8 == 1) begin
                $fdisplay(test.log_file, "END OF READING 8, time = %0d", $time/2);
                $fdisplay(test.log_file, "------------------------------------------");
                $fdisplay(test.log_file, "");

                result_for_reading_8 = d1[7:0];
                reading_8 = 0;
            end else if (reading_16 == 1) begin
                $fdisplay(test.log_file, "END OF READING 16, time = %0d", $time/2);
                $fdisplay(test.log_file, "------------------------------------------");
                $fdisplay(test.log_file, "");

                result_for_reading_8 = d1[15:0];
                reading_16 = 0;
            end else if (writing_32 == 1) begin
                $fdisplay(test.log_file, "END OF WRITING 32, time = %0d", $time/2);
                $fdisplay(test.log_file, "------------------------------------------");
                $fdisplay(test.log_file, "");

                inner_d1 = 'z;
                writing_32 = 0;
            end
        end
    end

    task read_data_8(reg[`ADDR1_BUS_SIZE + `OFFSET_SIZE -1 : 0] from);
        $fdisplay(test.log_file, "");
        $fdisplay(test.log_file, "------------------------------------------");
        $fdisplay(test.log_file, "START OF READING 8, time = %0d", $time/2);

        wait(clk == 1);

        inner_c1 = `C1_READ8;
        inner_a1 = from[`ADDR1_BUS_SIZE + `OFFSET_SIZE -1 : `OFFSET_SIZE];

        `delay(2,1);

        inner_c1 = 'z;
        inner_d1 = 'z;
      	inner_a1 = from[`OFFSET_SIZE-1:0];

        reading_8 = 1;
      	wait(reading_8 == 0);
    endtask

    task read_data_16(reg [`ADDR1_BUS_SIZE + `OFFSET_SIZE -1 : 0] from);
        $fdisplay(test.log_file, "");
        $fdisplay(test.log_file, "------------------------------------------");
        $fdisplay(test.log_file, "START OF READING 16, time = %0d", $time/2);

        wait(clk == 1);

        inner_a1 = from[`ADDR1_BUS_SIZE + `OFFSET_SIZE -1 : `OFFSET_SIZE];
        inner_c1 = `C1_READ16;
        
        `delay(2,1);

        inner_a1 = from[`OFFSET_SIZE-1:0];
        inner_c1 = 'z;
        inner_d1 = 'z;

        reading_16 = 1;
        wait(reading_16 == 0);
    endtask

    task write_data_32(reg [`ADDR1_BUS_SIZE + `OFFSET_SIZE -1 : 0] to, reg[31:0] data);
        $fdisplay(test.log_file, "");
        $fdisplay(test.log_file, "------------------------------------------");
        $fdisplay(test.log_file, "START OF WRITING 32, time = %0d", $time/2);

        wait(clk == 1);

        inner_a1 = to[`ADDR1_BUS_SIZE + `OFFSET_SIZE -1 : `OFFSET_SIZE];
        inner_c1 = `C1_WRITE32_OR_RESPONSE;
        inner_d1 = data[`DATA1_BUS_SIZE - 1:0];

        `delay(2,1);

        inner_a1 = to[`OFFSET_SIZE-1:0];
        inner_c1 = 'z;
        inner_d1 = data[`DATA1_BUS_SIZE*2-1:`DATA1_BUS_SIZE];
        
        writing_32 = 1;
        wait(writing_32 == 0);
    endtask

    task task_simulation;
        $fdisplay(test.log_file, "START SIMULATION, time = %0d", $time/2);

        additional_tick_counter += 2; //инициализация pa, pc

        for (int y = 0; y < M; y++) begin
            for (int x = 0; x < N; x++) begin
                pb = b;
                s = 0;

                additional_tick_counter += 2; //инициализация b, s

                for (int k = 0; k < K; k++) begin
                    read_data_8(pa + k); 
                    read_data_16(pb + 2*x); 

                    s += result_for_reading_8 * result_for_reading_16; 

                    additional_tick_counter += 5; //умножение
                    additional_tick_counter += 1; //сложение

                    pb += N * 2; 

                    additional_tick_counter += 1; //сложение
                    additional_tick_counter += 1; //итерация цикла
                end

                write_data_32(pc + x * 4, s);
            
                additional_tick_counter += 1; //итерация цикла
            end

            pa += K;
            additional_tick_counter += 1; //сложение

            pc += N * 4;
            additional_tick_counter += 1; //сложение

            additional_tick_counter += 1; //итерация цикла
        end

        additional_tick_counter += 1; //выход из функции

        $fdisplay(test.log_file, "END SIMULATION, time = %0d", $time/2);
    endtask
endmodule

module cache(input clk, input wire [`ADDR1_BUS_SIZE-1 : 0] a1, inout wire [`DATA1_BUS_SIZE-1 : 0] d1, inout wire [`CTR1_BUS_SIZE-1 : 0] c1, output wire [`ADDR2_BUS_SIZE-1 : 0] a2, inout wire [`DATA2_BUS_SIZE-1 : 0] d2, inout wire [`CTR2_BUS_SIZE-1 : 0] c2, input c_dump, input reset);
    reg [`WHOLE_CACHE_LINE_SIZE_IN_BITS - 1 : 0] cache_data [`CACHE_SETS_COUNT - 1 : 0][`CACHE_WAY-1:0];
    bit lru [`CACHE_SETS_COUNT - 1: 0]; 
    bit[`MAX_POSSIBLE_SIZE_OF_REQUESTED_DATA-1:0] inner_data;

    integer hit = -1;
    integer command = 0;
    integer writing = 0;
    integer reading = 0;

    bit [`CACHE_TAG_SIZE -1:0] tag;
    bit [`SET_SIZE -1:0] set;
    bit [`OFFSET_SIZE-1:0] offset;

    reg [`CTR2_BUS_SIZE - 1 : 0] inner_c2 = 'z;
    reg [`DATA2_BUS_SIZE - 1 : 0] inner_d2 = 'z;
    reg [`ADDR2_BUS_SIZE -1:0] inner_a2 = 'z;
    reg [`DATA1_BUS_SIZE - 1 : 0] inner_d1 = 'z;
    reg [`CTR1_BUS_SIZE - 1 : 0] inner_c1 = 'z;

    assign c2 = inner_c2;
    assign d2 = inner_d2;
    assign a2 = inner_a2;
    assign d1 = inner_d1;
    assign c1 = inner_c1;

    integer cacheHitCounter = 0;
    integer cacheMissCounter = 0;

    int i = 0;

    initial begin    
        $fdisplay(test.log_file, "");
        $fdisplay(test.log_file, "----------------------------------");
        $fdisplay(test.log_file, "INIT OF CACHE, t = %0d", $time/2);
        for (int outer = 0; outer < `CACHE_SETS_COUNT; outer++) begin
            for (int inner = 0; inner < `CACHE_WAY; inner++) begin
                cache_data[outer][inner] = 0;
            end
            lru[outer] = 0;
        end
        $fdisplay(test.log_file, "----------------------------------");
    end 

    always @(clk) begin
        if (clk == 0 && reading == 1 && c2==`C2_RESPONSE) begin
            for (int i = 0; i < `SEND_FROM_MEM; i++) begin 
                cache_data[set][hit][`DATA2_BUS_SIZE * i +: `DATA2_BUS_SIZE] = d2;

                `delay(2,0);
            end
            reading = 0;
        end else if (writing == 1 && clk == 1) begin
            for (int i = 0; i < `SEND_FROM_MEM; i++) begin 
                inner_d2 = cache_data[set][hit][`DATA2_BUS_SIZE * i +: `DATA2_BUS_SIZE];

                `delay(2,1);
                
                inner_c2 = 'z;
                inner_a2 = 'z;
            end
            writing = 2;
        end
    end

    always @(negedge clk) begin
        if (writing == 2 && c2==`C2_RESPONSE) begin
            writing = 0;
        end 
    end

    always @(posedge c_dump) begin
        $fdisplay(test.log_file, "");
        $fdisplay(test.log_file, "C_DUMP, time = %0d", $time/2);

        for (int i = 0; i < `CACHE_SETS_COUNT; i++) begin
            $fdisplay(test.cdump_file, "line %d: %d %d %d %d", 2*i, cache_data[i][0][127:96], cache_data[i][0][95:64], cache_data[i][0][63:32], cache_data[i][0][31:0]);
            $fdisplay(test.cdump_file, "line %d: %d %d %d %d", 2*i + 1, cache_data[i][1][127:96], cache_data[i][1][95:64], cache_data[i][1][63:32], cache_data[i][1][31:0]);
        end
    end

    always @(posedge reset) begin
        $fdisplay(test.log_file, "RESET, time = %0d", $time/2);
        for (int outer = 0; outer < `CACHE_SETS_COUNT; outer++) begin
            for (int inner = 0; inner < `CACHE_WAY; inner++) begin
                cache_data[outer][inner] = 0;
            end
            lru[outer] = 0;
        end
    end

    always @(negedge clk) begin
        case (c1)
        `C1_READ8, `C1_READ16, `C1_READ32: begin
            command = c1;
            set[`SET_SIZE-1:0] = a1[`SET_SIZE-1:0];
            tag[`CACHE_TAG_SIZE-1:0] = a1[`ADDR1_BUS_SIZE-1:`SET_SIZE];

            `delay(2,0);

            offset[`OFFSET_SIZE-1:0] = a1[`OFFSET_SIZE-1:0];

            `delay(1,0);

            hit = -1;
            inner_c1 = `C1_NOP;

            i = 0;

            while (hit == -1 && i < `CACHE_WAY) begin
                if (cache_data[set][i][`CACHE_TAG_SIZE + `CACHE_LINE_SIZE_IN_BITS -1:`CACHE_LINE_SIZE_IN_BITS] == tag) begin 
                    if (cache_data[set][i][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID]) begin
                        $fdisplay(test.log_file, "");
                        $fdisplay(test.log_file, "HIT CACHE, time = %0d", $time/2);

                        lru[set] = i;

                        cacheHitCounter++;

                        `delay((`CACHE_HIT_RESPONSE_TIME - 2)* 2, 1);
                        hit = i;
                    end
                end
                i++;
            end

            //miss
            if (hit == -1) begin
                $fdisplay(test.log_file, "");
                $fdisplay(test.log_file, "CACHE MISS, time = %0d", $time/2);

                cacheMissCounter++;

                hit = 1 - lru[set];

                `delay((`CACHE_MIS_RESPONSE_TIME - 2)* 2, 0);

                if (cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID] && cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID - `DIRTY]) begin
                    inner_a2[`SET_SIZE - 1: 0] = set;
                    inner_a2[`ADDR2_BUS_SIZE-1:`SET_SIZE] = cache_data[set][hit][`CACHE_LINE_SIZE_IN_BITS + `CACHE_TAG_SIZE - 1 : `CACHE_LINE_SIZE_IN_BITS];
                    inner_c2 = `C2_WRITE_LINE;

                    writing = 1;
                    wait(writing == 0);

                    `delay(1,0);
                end

                inner_a2[`SET_SIZE - 1: 0] = set;
                inner_a2[`ADDR2_BUS_SIZE-1:`SET_SIZE] = tag;
                inner_c2 = `C2_READ_LINE;
                
                `delay(2,1);

                inner_c2 = 'z;
                inner_a2 = 'z;
                inner_d2 = 'z;

                reading = 1;
                wait(reading == 0);

                cache_data[set][hit][`CACHE_LINE_SIZE_IN_BITS + `CACHE_TAG_SIZE] = 0;
                cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS-`VALID] = 1;
                cache_data[set][hit][`CACHE_TAG_SIZE+`CACHE_LINE_SIZE_IN_BITS-1:`CACHE_LINE_SIZE_IN_BITS] = tag;

                lru[set] = hit;

                `delay(1,0);
            end

            inner_c1 = `C1_WRITE32_OR_RESPONSE;

            case (command)
                `C1_READ8: begin
                    inner_d1[7:0] = cache_data[set][hit][offset * `BYTE +: 8];
                end
                `C1_READ16: begin
                    inner_d1[15:0] = cache_data[set][hit][offset * `BYTE +: 16];
                end
                `C1_READ32: begin
                    inner_d1[15:0] = cache_data[set][hit][offset * `BYTE +: 16];
                    `delay(2,1);
                    inner_d1[15:0] = cache_data[set][hit][16 + offset +: 16];
                end
            endcase

            `delay(2,1);

            inner_c1 = 'z;
            inner_d1 = 'z;
        end 
        `C1_WRITE8, `C1_WRITE16, `C1_WRITE32_OR_RESPONSE: begin
            command = c1;
            set[`SET_SIZE-1:0] = a1[`SET_SIZE-1:0];
            tag[`CACHE_TAG_SIZE-1:0] = a1[`ADDR1_BUS_SIZE-1:`SET_SIZE];
            
            inner_data[15:0] = d1;

            `delay(2,0);

            offset[`OFFSET_SIZE-1:0] = a1[`OFFSET_SIZE-1:0];

            if (command == `C1_WRITE32_OR_RESPONSE) begin
                inner_data[31:16] = d1; 
            end
            
            `delay(1,0);

            hit = -1;
            inner_c1 = `C1_NOP;

            i = 0;

            while (hit == -1 && i < `CACHE_WAY) begin
                if (cache_data[set][i][`CACHE_TAG_SIZE + `CACHE_LINE_SIZE_IN_BITS -1:`CACHE_LINE_SIZE_IN_BITS] == tag) begin 
                    if (cache_data[set][i][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID]) begin
                        $fdisplay(test.log_file, "");
                        $fdisplay(test.log_file, "HIT CACHE, time = %0d", $time/2);

                        lru[set] = i;

                        cacheHitCounter++;

                        `delay((`CACHE_HIT_RESPONSE_TIME-2) * 2, 0);
                        hit = i;
                    end
                end
                i++;
            end

            //miss
            if (hit == -1) begin
                $fdisplay(test.log_file, "");
                $fdisplay(test.log_file, "CACHE MISS, time = %0d", $time/2);

                cacheMissCounter++;

                hit = 1 - lru[set];

                `delay((`CACHE_MIS_RESPONSE_TIME - 2) * 2, 0);

                if (cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID] && cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID - `DIRTY]) begin
                    inner_a2[`SET_SIZE - 1: 0] = set;
                    inner_a2[`ADDR2_BUS_SIZE-1:`SET_SIZE] = cache_data[set][hit][`CACHE_LINE_SIZE_IN_BITS + `CACHE_TAG_SIZE - 1 : `CACHE_LINE_SIZE_IN_BITS];
                    inner_c2 = `C2_WRITE_LINE;
                    
                    writing = 1;
                    wait(writing == 0);

                    `delay(1,0);
                end

                inner_a2[`SET_SIZE - 1: 0] = set;
                inner_a2[`ADDR2_BUS_SIZE-1:`SET_SIZE] = tag;

                inner_c2 = `C2_READ_LINE;

                `delay(2,1);
                
                inner_a2 = 'z;
                inner_c2 = 'z;
                inner_d2 = 'z;

                reading = 1;
                wait(reading == 0);

                cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS-`VALID] = 1;
                cache_data[set][hit][`CACHE_TAG_SIZE+`CACHE_LINE_SIZE_IN_BITS-1:`CACHE_LINE_SIZE_IN_BITS] = tag;

                lru[set] = hit;

                `delay(1,0);
            end

            cache_data[set][hit][`CACHE_TAG_SIZE + `CACHE_LINE_SIZE_IN_BITS] = 0;

            if (command == `C1_WRITE8) begin
                cache_data[set][hit][offset * 8 +: 8] = inner_data[7:0];
            end else if (command == `C1_WRITE16) begin
                cache_data[set][hit][offset * 8 +: 16] = inner_data[15:0];
            end else if (command == `C1_WRITE32_OR_RESPONSE) begin
                cache_data[set][hit][offset * 8 +: 32] = inner_data[31:0];
            end

            inner_c1 = `C1_WRITE32_OR_RESPONSE;

            `delay(2,1);

            inner_c1 = 'z;
            inner_d1 = 'z;
        end
        `C1_INVALIDATE_LINE: begin
            $fdisplay(test.log_file, "");
            $fdisplay(test.log_file, "INVELIDATE LINE, time = %0d", $time/2);
            
            command = inner_c1;

            set[`SET_SIZE-1:0] = a1[`SET_SIZE-1:0];
            tag[`CACHE_TAG_SIZE-1:0] = a1[`ADDR1_BUS_SIZE-1:`SET_SIZE];
            
            `delay(2,0);
            
            offset[`OFFSET_SIZE-1:0] = a1[`OFFSET_SIZE-1:0];

            `delay(1,0);

            hit = -1;
            inner_c1 = `C1_NOP;

            for (int i = 0; i < `CACHE_WAY && (hit==-1); i++) begin 
                if (cache_data[set][i][`CACHE_TAG_SIZE + `CACHE_LINE_SIZE_IN_BITS -1:`CACHE_LINE_SIZE_IN_BITS] == tag) begin 
                    if (cache_data[set][i][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID]) begin
                        lru[set] = i;

                        cacheHitCounter++; 

                        `delay(`CACHE_HIT_RESPONSE_TIME * 2 - 4, 0);

                        hit = i;

                        if (cache_data[set][hit][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID - `DIRTY]) begin
                            inner_a2[`SET_SIZE - 1: 0] = set;
                            inner_a2[`ADDR2_BUS_SIZE-1:`SET_SIZE] = tag;
                            inner_c2 = `C2_WRITE_LINE;

                            writing = 1;
                            wait(writing == 0);

                            `delay(1,0);
                        end

                        cache_data[set][hit][`CACHE_LINE_SIZE_IN_BITS + `CACHE_TAG_SIZE] = 0;
                        cache_data[set][i][`WHOLE_CACHE_LINE_SIZE_IN_BITS - `VALID] = 0;
                    end
                end
            end
        end
        endcase
    end
endmodule
 
module memory #(parameter _SEED = 225526) (input clk, input wire [`ADDR2_BUS_SIZE-1 : 0] a2, inout wire [`DATA2_BUS_SIZE-1 : 0] d2, inout wire [`CTR2_BUS_SIZE-1 : 0] c2, input m_dump, input reset);
    integer SEED = _SEED;

    logic [`BYTE -1:0] memory_data[`MEM_SIZE -1:0];

    reg [`DATA2_BUS_SIZE - 1 : 0] inner_d2 = 'z;
    reg [`CTR2_BUS_SIZE - 1 : 0] inner_c2 = 'z;

    assign c2 = inner_c2;
    assign d2 = inner_d2;

    bit [`ADDR2_BUS_SIZE-1:0] inner_a = 'z;

    initial begin    
        $fdisplay(test.log_file, "----------------------------------");
        $fdisplay(test.log_file, "INIT MEMORY, t = %0d", $time/2);

        for (int i = 0; i < (1 << `MEM_SIZE); i++) begin
            memory_data[i] = $random(SEED)>>16;  
        end
    end 

    int i;
    //прописать еще reset, dump

    always @(posedge m_dump) begin
        $fdisplay(test.log_file, "MDUMP, time = %0d", $time/2);

        for (i = 0; i < `MEM_SIZE; i++) begin
            $fdisplay(test.mdump_file, "line %d: %d", i, memory_data[i]);
        end
    end

    always @(posedge reset) begin
        $fdisplay(test.log_file, "RESET MEMORY, time = %0d", $time/2);

        SEED = _SEED;
        for (i = 0; i < `MEM_SIZE; i++) begin
            memory_data[i] = $random(SEED)>>16;  
        end
    end

    always @(negedge clk) begin
        case (c2)
            `C2_READ_LINE: begin
            $fdisplay(test.log_file, "", $time/2);
            $fdisplay(test.log_file, "READ FROM MEM, time = %0d", $time/2);

            inner_a = a2;

            `delay(1,0);
            
            inner_c2 = `C2_NOP;

            `delay(`MEMCTR_RESPONSE_TIME*2, 1);

            inner_c2 = `C2_RESPONSE;

            for (int i = 0; i < `SEND_FROM_MEM; i++) begin
                inner_d2[`BYTE-1:0] = memory_data[inner_a * (1<<`OFFSET_SIZE) + 2 * i];
                inner_d2[`DATA2_BUS_SIZE-1:`BYTE] = memory_data[inner_a * (1<<`OFFSET_SIZE) + 2 * i + 1];

                `delay(2,1);
            end

            inner_c2 = 'z;
            inner_d2 = 'z;
            inner_a = 'z;
            end
            `C2_WRITE_LINE: begin
            $fdisplay(test.log_file, "");
            $fdisplay(test.log_file, "WRITE TO MEM, time = %0d", $time/2);

            inner_a = a2;

            for (int i = 0; i < `SEND_FROM_MEM; i++) begin
                memory_data[inner_a * (1<<`OFFSET_SIZE) + 2 * i] = inner_d2[`BYTE-1:0];
                memory_data[inner_a * (1<<`OFFSET_SIZE) + 2 * i + 1] = inner_d2[`DATA2_BUS_SIZE-1:`BYTE];
                `delay(2,0);
            end

            `delay(`MEMCTR_RESPONSE_TIME*2 - `SEND_FROM_MEM*2,1);

            inner_c2 = `C2_RESPONSE;

            `delay(2,1);

            inner_c2 = 'z;
            inner_a = 'z;
        end
        endcase
    end
endmodule

