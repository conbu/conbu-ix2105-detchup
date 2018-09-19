require "optparse"
require "erb"
require "json"
require "ipaddress"
require "pty"
require "expect"

Signal.trap("INT") { exit }

# usage: 
#   sudo ruby ./conbu-ix2025-detchup.rb -c [config] -t [template] -i [ix2025] -C [console device]
# example:
#   sudo ruby ./conbu-ix2025-detchup.rb -c config.json -t template.txt -s SW102 -C /dev/ttyUSB0

params = ARGV.getopts("c:t:i:C:")
if params.values.include?(nil)
  STDERR.puts "ERROR: argument is missing"
  exit 1
end

p params

config_file = params["c"]
$config = JSON.load(File.open(config_file).read)
template_file = params["t"]
$template = File.open(template_file).read
$target_ix2025 = params["i"]
$serialdev = params["C"]


common = $config["common"]
my = $config[$target_ix2025]
if my.nil?
  STDERR.puts "ERROR: target ix2025 not found #{$target_ix2025}"
  exit 1
end

# prepare per-sw
## hostname
my["hostname"] = $target_ix2025
## mgmt-prefix => mgmt-addr-host
my["mgmt-addr-host"] = IPAddress(my["mgmt-prefix"]).address
## user-prefix => user-addr-host
my["user-addr-host"] = IPAddress(my["user-prefix"]).address

puts "========== COMMON CONFIG =========="
puts JSON.pretty_generate(common)
puts "======== IX2025 (#{$target_ix2025}) specific ========"
puts JSON.pretty_generate(my)
puts "=" * 40


# generate config
erb = ERB.new($template, nil, "-")
config_text = erb.result(binding)
config_lines = config_text.split("\n").map{|line|
  case line.strip
  when /^!$/
    "exit"
  when /^$/
    nil
  else
    line.strip
  end
}.compact
puts "========== GENERATED CONFIG =========="
puts config_lines.join("\n")
puts "======================================"

puts "press any key to continue, or ^C to quit"
gets

cmd = "cu -l #{$serialdev} -s 9600"
puts cmd
PTY.spawn(cmd) do |rf, wf, pid|
  wf.sync = true
  $expect_verbose = true

  wf.puts ""
  wf.puts ""
  wf.puts ""

  config_ok = false
  fail_cnt = 0
  while !config_ok
    rf.expect(/(\(config\)#|#|>)$/) do |pattern|
      puts "patt => #{pattern}"
      unless pattern
        fail_cnt += 1
        next if fail_cnt < 10
        exit
      end
      case pattern[-1]
      when "#"
        wf.puts "enable-config"
        sleep 0.5
      when "(config)#"
        config_ok = true
      else
        puts "WTF"
        exit 10
      end
    end
  end

  while line = config_lines.shift
    rf.expect(/(#)$/) do
      #puts "CONFIG => #{line}"
      wf.puts(line)
    end
    sleep 0.5
  end

  rf.expect(/(#)$/) do
    wf.puts "exit"
  end
  rf.expect(/(#)$/) do
    wf.puts "exit"
  end

  wf.close
  rf.close
end

puts ""
puts ""
puts "done"
puts "!!!!! don't forget to WRITE MEMORY !!!!"
