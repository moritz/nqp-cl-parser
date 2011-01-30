class CLIParseResult {
    has @!arguments;
    has %!options;

    method init() {
        @!arguments := [];
        %!options := pir::new('Hash');
    }

    method arguments() { @!arguments }
    method options()   { %!options   }

    method add-argument($x) {
        pir::push__vPP(@!arguments, $x);
    }

    method add-option($name, $value) {
        # how I miss p6's Hash.push

        if pir::exists(%!options, $name) {
            my $t := pir::typeof(%!options);
            say($t);
            if $t eq 'ResizablePMCArray' {
                pir::push(%!options{$name}, $value);
            } else {
                %!options{$name} := [ %!options{$name}, $name ];
            }
        } else {
            %!options{$name} := $value;
        }
    }
}

class CommandLineParser {
    has @!specs;
    has %!options;
    has %!stopper;
    has $!stop-after-first-arg;

    method new(@specs) {
        my $obj := self.CREATE;
        $obj.BUILD(specs => @specs);
        $obj;
    }

    method stop-after-first-arg() {
        $!stop-after-first-arg := 1;
    }

    method BUILD(:@specs) {
        @!specs := @specs;
        %!stopper{'--'} := 1;
        $!stop-after-first-arg := 0;
        self.init();
    }
    method add-stopper($x) {
        %!stopper{$x} := 1;
    }

    method init() {
        for @!specs {
            my $i := pir::index($_, '=');
            my $type;
            if $i < 0 {
                $type := 'b';
            } else {
                $type := pir::substr($_, $i + 1);
                $_    := pir::substr($_, 0, $i);
            }
            %!options{$_} := $type;
        }
    }

    method is-option($x) {
        return 0 if $x eq '-' || $x eq '--';
        return 1 if pir::substr($x, 0, 1) eq '-';
        0;
    }

    method wants-value($x) {
        my $spec := %!options{$x};
        $spec eq 's';
    }

    method parse(@args) {
        my $i := 0;
        my $arg-count := +@args;

        my $result := CLIParseResult.new();
        $result.init();

        # called when an option expects a value after it
        sub get-value($opt) {
            if $i == $arg-count - 1 {
                pir::die("Option $opt needs a value");
            } elsif self.is-option(@args[$i + 1]) {
                pir::die("Option $opt needs a value, but is followed by an option");
            } elsif %!stopper{@args[$i + 1]} {
                pir::die("Option $opt needs a value, but is followed by a stopper");
            } else {
                $i++;
                @args[$i];
            }
        }

        # called after a terminator that declares the rest
        # as not containing any options
        sub slurp-rest() {
            $i++;
            while $i < $arg-count {
                $result.add-argument(@args[$i]);
                $i++;
            }
        }

        while $i < $arg-count {
            my $cur := @args[$i];
            if self.is-option($cur) {
                if pir::substr($cur, 0, 2) eq '--' {
                    # long option
                    my $opt := pir::substr(@args[$i], 2);
                    my $idx := pir::index($opt, '=');
                    my $value := 1;
                    my $has-value := 0;

                    if $idx >= 0 {
                        $value     := pir::substr($opt, $idx + 1);
                        $opt       := pir::substr($opt, 0,      $idx);
                        $has-value := 1;
                    }
                    pir::die("Illegal option --$opt") unless pir::exists(%!options, $opt);
                    pir::die("Option --$opt does not allow a value") if %!options{$opt} ne 's' && $has-value;
                    if !$has-value && self.wants-value($opt) {
                        $value := get-value("--$opt");
                    }
                    $result.add-option($opt, $value);
                    slurp-rest if %!stopper{"--$opt"};
                } else {
                    my $opt := pir::substr($cur, 1);
                    if pir::length($opt) == 1 {
                        # not grouped, so it might have a value
                        pir::die("No such option -$opt") unless %!options{$opt};
                        if self.wants-value($opt) {
                            $result.add-option($opt,
                            get-value("-$opt"));
                        } else {
                            $result.add-option($opt, 1);
                        }
                        slurp-rest() if %!stopper{"-$opt"};
                    } else {
                        # length > 1, so the options are grouped
                        my $iter := pir::iter__pp($opt);
                        while $iter {
                            my $o := pir::shift($iter);
                            pir::die("Option -$o requires a value and cannot be grouped") if self.wants-value($o);
                            $result.add-option($o, 1);
                        }
                    }
                }
            } elsif %!stopper{$cur} {
                slurp-rest();
            } else {
                $result.add-argument($cur);
                slurp-rest() if $!stop-after-first-arg;
            }
            $i++;
        }
        return $result;
    }
}

plan(18);

my $x := CommandLineParser.new(['a', 'b', 'e=s', 'target=s', 'verbose']);
my $r := $x.parse(['-a', 'b']);

ok($r.isa(CLIParseResult), 'got the right object type back');
ok($r.arguments()[0] eq 'b', '"b" got classified as argument')
    || say("# arguments: '", pir::join('|', $r.arguments()), "'");
ok($r.options(){'a'} == 1, '-a is an option');


$r := $x.parse(['-ab']);

ok($r.options(){'a'} == 1, '-ab counts as -a (clustering)');
ok($r.options(){'b'} == 1, '-ab counts as -b (clustering)');

$r := $x.parse(['-e', 'foo bar', 'x']);

ok($r.options(){'e'} eq 'foo bar', 'short options + value');
ok(+$r.arguments == 1, 'one argument remaining');

$r := $x.parse(['--verbose', '--target=foo']);
ok($r.options{'verbose'} == 1,    'long option without value');
ok($r.options{'target'} eq 'foo', 'long option with value supplied via =');

$r := $x.parse(['--target', 'foo', 'bar']);
ok($r.options{'target'} eq 'foo', 'long option with value as separate argument');
ok(+$r.arguments == 1, '...on remaining argument');
ok($r.arguments[0] eq 'bar', '...and  it is the right one');

$r := $x.parse(['a', '--', 'b', '--target', 'c']);
ok(+$r.arguments == 4, 'got 4 arguments, -- does not count');
ok(pir::join(',',$r.arguments) eq 'a,b,--target,c', '... and the right arguments');

$x.add-stopper('-e');

$r := $x.parse(['-e', 'foo', '--target', 'bar']);
ok(+$r.arguments == 2,
    'if -e is stopper, everything after its value is an argument');
ok($r.options{'e'} eq 'foo', '... and -e still got the right value');

$x.add-stopper('stopper');
$r := $x.parse(['stopper', '--verbose']);
ok(+$r.arguments == 1, 'non-option stopper worked');

$x.stop-after-first-arg;

$r := $x.parse(['-a', 'script.pl', '--verbose']);
ok(pir::join(',', $r.arguments) eq 'script.pl,--verbose',
    'stop-after-first-arg');

# TODO: tests for long options as stoppers

#for $r.options() {
#    say($_.key, ": ", $_.value, ' (', pir::typeof($_.value), ')');
#}


# vim: ft=perl6
