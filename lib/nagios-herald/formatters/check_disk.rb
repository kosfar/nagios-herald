# CheckDisk formatter
# Colorizes and bolds text generated by the 'check_disk' NRPE check.

module NagiosHerald
  class Formatter
    class CheckDisk < NagiosHerald::Formatter
      include NagiosHerald::Logging

      # Public: Gets information about each of the partitions in the check's output.
      # Parses the partition name and free space value and percentage
      #
      # Expects the check's output looks similar to one of the following cases:
      # Simple output - ends with :
      # DISK CRITICAL - free space: / 7002 MB (18% inode=60%): /data 16273093 MB (26% inode=99%):
      # Long output - delimited by |
      # DISK CRITICAL - free space: / 7051 MB (18% inode=60%); /data 16733467 MB (27% inode=99%);| /=31220MB;36287;2015;0;40319 /dev/shm=81MB;2236;124;0;2485 /data=44240486MB;54876558;3048697;0;60973954
      #
      # input - A string containing partition data to match.
      #
      # Returns an array of hash data per partition
      def get_partitions_data(input)
        partitions = []
        space_data = /.*free space:\s*(?<size>[^|:]*)(\||:)/.match(input)
        if space_data
          space_str = space_data[:size]
          splitter = (space_str.count(';') > 0)? ';' : ':'
          space_str.split(splitter).each do |part|
            partition_regex = Regexp.new('(?<partition>\S+)\s+(?<free_unit>.*)\s+\((?<free_percent>\d+)\%.*')
            data = partition_regex.match(part)
            hash_data = Hash[ data.names.zip( data.captures ) ]
            partitions << hash_data if hash_data
          end
        end
        return partitions
      end

      # Public: Generates an image of stack bars for all disk partitions.
      #
      # partitions_data - The array of hashes generated by #get_partitions_data
      #
      # Returns the filename of the generated image or nil if the image was not generated.
      def get_partitions_stackedbars_chart(partitions_data)
        # Sort results by the most full partition
        partitions_data.sort! { |a,b| a[:free_percent] <=> b[:free_percent] }
        # generate argument as string
        volumes_space_str = partitions_data.map {|x| "#{x[:partition]}=#{100 - x[:free_percent].to_i}"}.compact
        output_file = File.join(@sandbox, "host_status.png")
        command = ""
        command += NagiosHerald::Util::get_script_path('draw_stack_bars')
        command +=  " --width=500 --output=#{output_file} "
        command += volumes_space_str.join(" ")
        %x(#{command})
        if $? == 0
          return output_file
        else
          return nil
        end
      end

      # Public: Overrides Formatter::Base#additional_info.
      # Calls on methods defined in this class to generate stack bars and download
      # Ganglia graphs.
      #
      # Returns nothing. Updates the formatter content hash.
      def additional_info
        section = __method__
        output = get_nagios_var("NAGIOS_#{@state_type}OUTPUT")
        add_text(section, "Additional Info:\n #{unescape_text(output)}\n\n") if output

        # Collect partitions data and plot a chart
        # if the check has recovered, $NAGIOS_SERVICEOUTPUT doesn't contain the data we need to parse for images; just give us the A-OK message
        if output =~ /DISK OK/
            add_html(section, %Q(Additional Info:<br><b><font color="green"> #{output}</font><br><br>))
        else
          partitions = get_partitions_data(output)
          partitions_chart = get_partitions_stackedbars_chart(partitions)
          if partitions_chart
            add_html(section, "<b>Additional Info</b>:<br> #{output}<br><br>") if output
            add_attachment partitions_chart
            add_html(section, %Q(<img src="#{partitions_chart}" width="500" alt="partitions_remaining_space" /><br><br>))
          else
            add_html(section, "<b>Additional Info</b>:<br> #{output}<br><br>") if output
          end
        end
      end

      # Public: Overrides Formatter::Base#additional_details.
      # Calls on methods defined in this class to colorize and bold the `df` output
      # generated by the check_disk NRPE check.
      #
      # Returns nothing. Updates the formatter content hash.
      def additional_details
        section = __method__
        long_output = get_nagios_var("NAGIOS_LONG#{@state_type}OUTPUT")
        lines = long_output.split('\n') # the "newlines" in this value are literal '\n' strings
        # if we've been passed threshold information use it to color-format the df output
        threshold_line = lines.grep( /THRESHOLDS - / ) # THRESHOLDS - WARNING:50%;CRITICAL:40%;
        threshold_line.each do |line|
          /WARNING:(?<warning_threshold>\d+)%;CRITICAL:(?<critical_threshold>\d+)%;/ =~ line
          @warning_threshold = warning_threshold
          @critical_threshold = critical_threshold
        end

        # if the thresholds are provided, color me... badd!
        if @warning_threshold and @critical_threshold
          output_lines = []
          output_lines << "<pre>"
          lines.each do |line|
            if line =~ /THRESHOLDS/
              output_lines << line
              next  # just throw this one in unchanged and move along
            end
            /(?<percent>\d+)%/ =~ line
            if defined?( percent ) and !percent.nil?
              percent_free = 100 - percent.to_i
              if percent_free <= @critical_threshold.to_i
                output_line = %Q(<b><font color="red">#{line}</font>  Free disk space <font color="red">(#{percent_free}%)</font> is <= CRITICAL threshold (#{@critical_threshold}%).</b>)
                output_lines << output_line
              elsif percent_free <= @warning_threshold.to_i
                output_line = %Q(<b><font color="orange">#{line}</font>  Free disk space <font color="orange">(#{percent_free}%)</font> is <= WARNING threshold ( #{@warning_threshold}%).</b>)
                output_lines << output_line
              else
                output_lines << line
              end
            else
              output_lines << line
            end
          end

          output_lines << "</pre>"
          output_string = output_lines.join( "<br>" )
          add_html(section, "<b>Additional Details</b>:")
          add_html(section, output_string)
        else  # just spit out what we got from df
          add_text(section, "Additional Details:\n#{unescape_text(long_output)}\n") if long_output
          add_html(section, "<b>Additional Details</b>:<br><pre>#{unescape_text(long_output)}</pre><br><br>") if long_output
        end
        line_break(section)
      end

    end
  end
end
