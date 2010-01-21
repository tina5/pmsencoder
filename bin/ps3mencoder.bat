@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/bin/env perl
#line 15

use strict;
use warnings;

use Cwd qw(getcwd);
use IPC::Cmd qw(can_run run); # core since 5.10.0
use POSIX qw(strftime);

use IO::All;
use List::MoreUtils qw(first_index);
use LWP::Simple qw(get head);
use YAML qw(LoadFile);

my $CWD               = getcwd();          # current working directory
my $DEFAULT_FPS       = 25;                # default framerate
my $LOGFILE_PATH      = 'ps3mencoder.log'; # save alongside debug.log
my $LOGFILE           = io($LOGFILE_PATH); # debug log
my $VERSION           = '0.20';            # logged to aid diagnostics
my $WINDOWS           = $^O eq 'MSWin32';  # is this running on Windows?
my $YOUTUBE           = qr{http://(?:\w+\.)?youtube\.com/watch\?v=([^&]+)}; # YouTube page (HTML)
my @YOUTUBE_FORMATS   = qw(22 18 6 5);     # YouTube formats id descending order of preference (see below)

=for comment

    mencoder http://movies.apple.com/movies/foo.mov -prefer-ipv4 \
        -nocache -quiet -oac lavc -of lavf -lavfopts format=dvd -ovc lavc \
        -lavcopts vcodec=mpeg2video:vbitrate=4096:threads=2:acodec=ac3:abitrate=128 \
        -ofps 24000/1001 -o /tmp/javaps3media/mencoder1261801759641

=cut

###################################################################################

sub debug($) {
    my $message = shift;
    my $now = strftime("%Y-%m-%d %H:%M:%S", localtime);

    $LOGFILE->append("$now: $VERSION: $$: $message", $/);
}

sub fatal($) {
    my $message = shift;

    debug "ERROR: $message";

    die "$0: $VERSION: $$: ERROR: $message", $/;
}

sub set($;$) {
    my ($name, $value) = @_;
    my $index = first_index { $_ eq $name } @ARGV;

    if ($index == -1) {
        if (defined $value) {
            debug "adding $name $value";
            push @ARGV, $name, $value;
        } else {
            debug "adding $name";
            push @ARGV, $name;
        }
    } elsif (defined $value) {
        if (ref($value) eq 'CODE') {
            local $_ = $ARGV[ $index + 1 ];
            my $old = $_;
            $value->();
            $ARGV[ $index + 1 ] = $_;
            debug "replaced $old with $_ in $name";
        } else {
            debug "setting $name to $value";
            $ARGV[ $index + 1 ] = $value;
        }
    }
}

sub subst($$$) {
    my ($name, $search, $replace) = @_;
    my $index = first_index { $_ eq $name } @ARGV;

    if ($index != -1) {
        debug "replacing $search with $replace in " . $ARGV[ $index + 1 ];
        $ARGV[ $index + 1 ] =~ s{$search}{$replace};
    }
}

sub add($;@) {
    my ($name, $value) = @_;

    if (defined $value) {
        debug "adding $name $value";
        push @ARGV, $name, $value;
    } else {
        debug "adding $name";
        push @ARGV, $name;
    }
}

# XXX unused
sub value($) {
    my $name = shift;
    my $index = first_index { $_ eq $name } @ARGV;

    if ($index == -1) {
        return undef;
    } else {
        return $ARGV[ $index + 1 ];
    }
}

sub isdef($) {
    my $name = shift;
    my $index = first_index { $_ eq $name } @ARGV;

    return ($index != -1);
}

sub isopt($) {
    my $arg = shift;
    return (defined($arg) && (substr($arg, 0, 1) eq '-'));
}

sub remove($) {
    my $name = shift;
    my @argv = @ARGV;
    my @keep;

    while (@argv) {
        my $arg = shift @argv;

        if (isopt($arg)) { # -foo ...
            if (@argv && not(isopt($argv[0]))) { # -foo bar
                my $value = shift @argv;

                if ($arg ne $name) {
                    push @keep, $arg, $value;
                }
            } elsif ($arg ne $name) { # just -foo
                push @keep, $arg;
            }
        } else {
            push @keep, $arg;
        }
    }

    if (@keep < @ARGV) {
        debug "removing $name";
        @ARGV = @keep;
    }
}

sub replace($@) {
    my ($old, @new) = @_;
    my $index = first_index { $_ eq $old } @ARGV;

    unless ($index == -1) {
        debug "replacing $old with @new";
        splice @ARGV, $index, 1, @new;
    }
}

sub mencoder(;$) {
    my $config = shift || {};
    my $mencoder = $config->{mencoder_path} || can_run('mencoder') || fatal("can't find mencoder");

    debug "exec: $mencoder" . (@ARGV ? " @ARGV" : '');

    # local $SIG{CHLD} = 'IGNORE'; # XXX try to ensure mencoder is reaped
    undef $!;
    my $ok = run(
        command => [ $mencoder, @ARGV ],
        verbose => 1
    );

    if ($ok) {
        debug('ok');
        exit 0;
    } else {
        fatal "can't exec mencoder: $?";
    }
}

=for comment

    {
        'profiles' => [
            {
                'mencoder' => {
                    '-quiet'   => undef,
                    'cache'    => '16384',
                    'lavcopts' => { '$' => ':level=41' }
                },
                'name' => 'Global',
                'uri'  => '^\\w+://.+$'
            },
            {
                'mencoder' => { 'user-agent' => 'Quicktime/7.6.4' },
                'name'     => 'Apple Trailers',
                'uri'      => '^http://(?:(?:movies|www)\\.)?apple\\.com/.+$'
            },
            {
                'mencoder' => { 'lavcopts' => { '4096' => '5086' } },
                'name'     => 'Apple Trailers HD',
                'uri'      => '^http://(?:(?:movies|www)\\.)?apple\\.com/.+\\.m4v$'
            }
        ],
        'version' => '0.2'
    }

=cut

sub process_config($) {
    my $uri = shift;
    my $config;

    if (-s 'ps3mencoder.yml') {
        debug 'loading config: ps3mencoder.yml';
        $config = eval { LoadFile('ps3mencoder.yml') };
    } elsif (-s 'ps3mencoder.conf') {
        debug 'loading config: ps3mencoder.conf';
        $config = eval { LoadFile('ps3mencoder.conf') };
    } else {
        debug "can't find ps3mencoder.conf or ps3mencoder.yml in $CWD";
    }

    fatal "can't load config: $@" if ($@);

    # FIXME: this blindly assumes the config file is sane at the moment
    # XXX use Kwalify?

    if (defined $uri) {
        if ($config) {
            my $profiles = $config->{profiles};

            if ($profiles) {
                for my $profile (@$profiles) {
                    my $profile_name = $profile->{name};
                    my $match = $profile->{uri};

                    if (defined($match) && ($uri =~ $match)) {
                        debug "matched profile: $profile_name";

                        while (my ($option_name, $option_value) = each (%{$profile->{mencoder}})) {
                            $option_name =~ s{^([-+]?)}{-};

                            if (ref $option_value) {
                                while (my ($search, $replace) = each (%$option_value)) {
                                    subst($option_name, $search, $replace);
                                }
                            } else {
                                my $op;
                               
                                if ($1 eq '-') {
                                    $op = \&remove;
                                } elsif ($1 eq '+') {
                                    $op = \&add;
                                } else {
                                    $op = \&set;
                                }

                                $op->($option_name, $option_value);
                            }
                        }
                    }
                }
            } else {
                debug 'no profiles defined'; 
            }
        } else {
            debug 'no config defined'; 
        }
    } else {
        debug 'no URI defined'; 
    }

    return $config; # may be undef
}

sub handle_youtube($$) {
    my ($uri, $config) = @_;
    # extract the media URI - see http://stackoverflow.com/questions/1883737/getting-an-flv-from-youtube-in-net
    my $id = $1;
    my $html = get($uri) || fatal "couldn't retrieve $uri";
    my ($signature) = $html =~ m{"t":\s*"([^"]+)"};
    my $found = 0;

    # via http://www.longtailvideo.com/support/forum/General-Chat/16851/Youtube-blocked-http-youtube-com-get-video
    #
    # No &fmt = FLV (very low)
    # &fmt=5  = FLV (very low)
    # &fmt=6  = FLV (doesn't always work)
    # &fmt=13 = 3GP (mobile phone)
    # &fmt=18 = MP4 (normal)
    # &fmt=22 = MP4 (hd)
    #
    # see also:
    #
    #     http://tinyurl.com/y8rdcoy
    #     http://userscripts.org/topics/18274

    for my $fmt (@YOUTUBE_FORMATS) {
        my $media_uri = "http://www.youtube.com/get_video?fmt=$fmt&video_id=$id&t=$signature";
        next unless (head $media_uri);
        $ARGV[0] = $media_uri;
        $found = 1;
        last;
    }

    fatal "can't retrieve YouTube video from $uri" unless ($found);
}

###################################################################################

$| = 1; # unbuffer output
$LOGFILE->append($/) if (-s $LOGFILE_PATH);

debug $0 . (@ARGV ? " @ARGV" : '');

my $uri = $ARGV[0];
my $config = process_config($uri); # load the config and process matching profiles

# web video streaming: fix mencoder options, handle YouTube videos, and process config file
if (isdef('-prefer-ipv4') && isdef('-ovc')) {
    remove('-nocache'); # this should *never* be set
    set('-ofps', $DEFAULT_FPS);

    # special-case YouTube
    # XXX add config support for this kind of handling (i.e. redirection)
    # if there are more examples like this

    if ($uri =~ $YOUTUBE) {
        handle_youtube($uri, $config);
    }
}

mencoder($config);

__END__
:endofperl
