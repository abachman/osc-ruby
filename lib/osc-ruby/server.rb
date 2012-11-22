module OSC
  class EndSignal; end

  class  Server
    def initialize( port )
      @port = port
      @socket = UDPSocket.new
      @socket.bind( '', @port )
      @matchers = []
      @queue = Queue.new

      @state = :initialized
    end

    def run
      @state = :starting
      start_dispatcher
      start_detector
    end

    def stop
      @state = :stopping

      stop_detector
      stop_dispatcher
    end

    def add_method( address_pattern, &proc )
      matcher = AddressPattern.new( address_pattern )
      @matchers << [matcher, proc]
    end

    def state; @state; end
private

    def start_detector
      begin
	      detector
      rescue
	      Thread.main.raise $!
      end
    end

    def start_dispatcher
      Thread.fork do
	      begin
	        dispatcher
	      rescue
	        Thread.main.raise $!
	      end

        @state = :stopped
      end
    end

    def stop_detector
      # send listening port a "CLOSE" signal on the open UDP port
      _closer = UDPSocket.new
      _closer.connect('', @port)
      _closer.puts "CLOSE-#{@port}"
      _closer.close unless _closer.closed? || !_closer.respond_to?(:close)
    end

    def stop_dispatcher
      @queue << :stop
    end

    def dispatcher
      loop do
	      mesg = @queue.pop
        if mesg.is_a?(Symbol) && mesg == :stop
          break
        else
          dispatch_message( mesg )
        end
      end
    end

    def dispatch_message( message )
      diff = ( message.time || 0 ) - Time.now.to_ntp

      if diff <= 0
        sendmesg(message)
      else # spawn a thread to wait until it's time
        Thread.fork do
    	    sleep( diff )
    	    sendmesg( mesg )
    	    Thread.exit
    	  end
      end
    end

    def sendmesg(mesg)
      @matchers.each do |matcher, proc|
	      if matcher.match?( mesg.address )
	        proc.call( mesg )
	      end
      end
    end

    def detector
      @state = :listening

      loop do
	      osc_data, network = @socket.recvfrom( 16384 )

        # quit if socket receives the close signal
        if osc_data == "CLOSE-#{@port}"
          @socket.close if !@socket.closed? && @socket.respond_to?(:close)
          break
        end

        begin
          ip_info = Array.new
          ip_info << network[1]
          ip_info.concat(network[2].split('.'))
          OSCPacket.messages_from_network( osc_data, ip_info ).each do |message|
            @queue.push(message)
          end
        rescue EOFError
        end
      end
    end

  end
end
