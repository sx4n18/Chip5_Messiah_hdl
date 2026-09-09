// very simpley mission counter that runs at 40 mhz with 45-bit
//

module mission_counter (
	input clk40m,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	output 		[44:0] 	mission_cnt
);



reg [45:0] actual_mission_cnt;

always @(posedge clk40m or negedge rst_n) begin 
	if(~rst_n) begin
		actual_mission_cnt <= '0;
	end else begin
		actual_mission_cnt <= actual_mission_cnt + 1;
	end
end


assign mission_cnt = actual_mission_cnt[45:1];

endmodule