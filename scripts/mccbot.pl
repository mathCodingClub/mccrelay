use Irssi;

use lib 'modules';

use Protocol::WebSocket::Client;
use IO::Socket;
use IO::Select;

use strict;

sub clean_eval {
    return eval shift;
}

my $irssi_config = '/home/acce/.mccrelay';

our %last_info;

our $s = IO::Socket::INET->new;
our $select = IO::Select->new;

our $webclient = Protocol::WebSocket::Client->new(url => 'ws://irc.mathcodingclub.com:8081/socket/index.php');

my %soc_funcs = (
    disconnect => sub {
	if((not $s->connected ))
	{
	    Irssi::print "Already disconnected";
	    say($last_info{'server'},$last_info{'target'}, "Already disconnected");
	}
else
{
    Irssi::print "Disconnecting";
      $webclient->write("Relay offline!");
      $webclient->disconnect;
  
      $s->shutdown(2);
      $s->close;

      $select->remove($s);
      say($last_info{'server'},$last_info{'target'}, "Relay offline!"); 
}
    },
    connect => sub {
	if($s->connected)
	{
	    Irssi::print "Already connected";
	    say($last_info{'server'},$last_info{'target'}, "Already connected");
	}
else
{
    Irssi::print "Connecting";
      $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => 8081, Proto => 'tcp', Blocking => 0);
      $select->add($s);

      $webclient = Protocol::WebSocket::Client->new(url => 'ws://irc.mathcodingclub.com:8081/socket/index.php');

$webclient->on(write => 
	       sub {
		   my $client = shift;
		   my ($buf) = @_;
		   
		   syswrite $s, $buf;
	       });

$webclient->on(read => 
	       sub {
		   my $client = shift;
		   my ($buf) = @_;

		   Irssi::print "Message from web: " . $buf;
		   if(%last_info)
{
   say($last_info{'server'},$last_info{'target'}, $buf); 

}
else
{
   Irssi::print "Need to get message from the channel first"; 
   syswrite $s, "Relay not initialized from the irc side";
}
	       });


      $webclient->connect;
      $webclient->on(
        connect => sub {
          $webclient->write("Relay online!");
          say($last_info{'server'},$last_info{'target'}, "Relay online!"); 
          $webclient->write("!iambot"); 

        }
      );
}
    },
    status => sub {
     if($s->connected)
     {
       say($last_info{'server'},$last_info{'target'}, "Relay online, handles:" . $select->count()); 
       $webclient->write("Relay online!");
     }
     else
     {
       say($last_info{'server'},$last_info{'target'}, "Relay offline, handles:" . $select->count()); 
     }
    }
    
    );



sub reply { my ($server, $target, $nick, $msg) = @_; $server->command("msg $target $nick: $msg") }
sub say   { my ($server, $target, $msg) = @_; $server->command("msg $target $msg") }
sub reply_private   { $_{server}->command("msg $_{nick} $_") for @_ }
sub match { $_{server}->masks_match("@_", $_{nick}, $_{address}) }

sub message {
    my ($server, $msg, $nick, $address, $target) = @_;

    $last_info{'server'} = $server;
    $last_info{'target'} = $target;
    $last_info{'msg'} = $msg;
    $last_info{'nick'} = $nick;
    $last_info{'address'} = $address;

    if($nick =~ m/Acce|Pekko/ && $msg =~ s/^%(connect|status|disconnect)\s*//)
    {
	my $command = $1;

	$soc_funcs{$command}->();
	
    }
    else
    {
	$webclient->write("< " . $nick . " > " . $msg) unless not $s->connected;
    }

    Irssi::print "message by $nick${\ ($target ? qq/ in $target/ : '') } on " .
                 "$server->{address}";

}

sub check_socket {

    foreach my $socket ($select->can_read(0.5)) {
	if (ref $socket eq 'IO::Socket::INET') {
	    Irssi::print("reading shit");
	    # read from websocket
	    $socket->sysread(my $buf, 1000);
	    Irssi::print("reading shit: " . $buf);
	    $webclient->read($buf);
	}
    }
}

Irssi::signal_add_last 'message public' => \&message;
Irssi::signal_add_last 'message private' => \&message;
Irssi::timeout_add(1000, 'check_socket', '');
