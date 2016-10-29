require_relative 'fusuma/version'
require_relative 'fusuma/action_stack'
require_relative 'fusuma/gesture_action'
require 'logger'
require 'open3'
require 'yaml'

# this is top level module
module Fusuma
  class << self
    def run
      @logger = Logger.new(STDOUT)
      read_libinput
    end

    private

    def read_libinput
      Open3.popen3(libinput_command) do |_i, o, _e, _w|
        o.each do |line|
          gesture_action = GestureAction.initialize_by_libinput(line, device_name)
          next if gesture_action.nil?
          @action_stack ||= ActionStack.new
          @action_stack.push gesture_action
          gesture_info = @action_stack.gesture_info
          trigger_keyevent(gesture_info) unless gesture_info.nil?
        end
      end
    end

    def libinput_command
      @libinput_command ||= "stdbuf -oL -- libinput-debug-events --device \
    /dev/input/#{device_name}"
    end

    def device_name
      return @device_name unless @device_name.nil?
      Open3.popen3('libinput-list-devices') do |_i, o, _e, _w|
        o.each do |line|
          extracted_input_device_from(line)
          next unless touch_is_available?(line)
          return @device_name
        end
      end
    end

    def extracted_input_device_from(line)
      return unless line =~ /^Kernel: /
      @device_name = line.match(/event[0-9]/).to_s
    end

    def touch_is_available?(line)
      return false unless line =~ /^Tap-to-click: /
      return false if line =~ %r{n/a}
      true
    end

    def trigger_keyevent(gesture_info)
      case gesture_info.action
      when 'swipe'
        swipe(gesture_info.finger, gesture_info.direction.move)
      when 'pinch'
        pinch(gesture_info.direction.pinch)
      end
    end

    def swipe(finger, direction)
      @logger.debug("finger: #{finger}, direction: #{direction.to_sym}")
      shortcut = event_map['swipe'][finger.to_i][direction]['shortcut']
      `xdotool key #{shortcut}`
    end

    def pinch(zoom)
      shortcut = event_map['pinch'][zoom]['shortcut']
      `xdotool key #{shortcut}`
    end

    def event_map
      @event_map ||= load_config
    end

    def load_config
      file = File.expand_path('../fusuma/config.yml', __FILE__)
      YAML.load_file(file)
    end
  end
end