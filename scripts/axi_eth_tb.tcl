set script_dir [file dirname [info script]]
set project_root ${script_dir}/..

create_project axi_eth_tb . -part xc7a35tcpg236-1 -force

set rtl_dir ${project_root}/rtl
set tb_dir ${project_root}/tb
set ip_dir ${project_root}/ip

add_files ${rtl_dir}/axi_eth.sv

read_ip ${ip_dir}/axi_ethernetlite_0.xci
generate_target all [get_ips axi_ethernetlite_0]

add_files -fileset sim_1 ${tb_dir}/axi_eth_tb.sv
set_property top axi_eth_tb [get_filesets sim_1]
launch_simulation
run 2us
