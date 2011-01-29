class CLIParseResult {
    has @!arguments;
    has %!options;
    has $!error;

    method init() {
        @!arguments := [];
        %!options := pir::new('Hash');
    }

    method arguments() { @!arguments }
    method options()   { @!options   }

    method add-argument($x) {
        pir::push__vPP(@!arguments, $x);
    }

    method add-option($name, $value) {
        # how I miss p6's Hash.push
        my $t := pir::typeof(%!options);
        if $t eq 'ResizablePMCArray' {
            pir::push(%!options{$name}, $value);
        } elsif $t eq 'Undef' {
            %!options{$name} := $value;
        } else {
            %!options{$name} := [ %!options{$name}, $name ];
        }
    }
}

class CommandLineParser {
    has @!specs;

    has %!short;
    has %!long;
    has %!either;

    has %!stopper;

    method new(:@specs) {
        my $obj := self.CREATE;
        $obj.BUILD(specs => @specs);
        $obj;
    }
    method BUILD(:@specs) {
        @!specs := @specs;
        %!stopper{'--'} := 1;
        self.init();
    }
    method set-stopper($x) {
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
            say("type: '$type'; option: '$_'");
            if pir::length($_) == 1 {
                %!short{$_} := $type;
            } else {
                %!long{$_}  := $type;
            }
        }
    }

    method is-option($x) {
        return 0 if $x eq '-' || $x eq '--';
        return 1 if pir::substr($x, 0, 1) eq '-';
        0;
    }

    method parse(@args) {
        my @rest;
        my $abort := 0;
        my $i := 0;
        my $arg-count := +@args;
        my $args-starting-from := $arg-count;
        my $looking_for := '';

        my %found-options;

        my $result := CLIParseResult.new();
        $result.init();
        while $i < $arg-count {
            say("looking at ", @args[$i]);

            if self.is-option(@args[$i]) {
                if pir::substr(@args[$i], 0, 2) eq '--' {
                    # long option
                    my $opt := pir::substr(@args[$i], 2);
                    my $idx := pir::index($opt, '=');
                    my $value := 1;
                    my $has-value := 0;
                    if $idx >= 0 {
                        $value     := pir::substr($opt, $idx + 1);
                        $opt       :=  pir::substr($opt, 0, $idx);
                        $has-value := 1;
                    }
                    pir::die("Illegal option --$opt") if pir::isa(%!long{$opt}, 'Undef');
                    pir::die("Option --$opt needs a value, but doesn't have one") if %!long{$opt} eq 's' && !$has-value;
                    pir::die("Option --$opt does not allow a value") if %!long{$opt} ne 's' && $has-value;

                    $result.add-option($opt, $value);
                } else {
                    for pir::split(pir::substr(@args[$i], 1), '') {
                        # TODO: check that it's ok that $_ doesn't have a
                        # value
                        $result.add-option($_, 1);

                    }
                }
            } else {
                $result.add-argument(@args[$i]);
            }
            $i++;
        }
        return $result;
    }
}

plan(3);

my $x := CommandLineParser.new(specs => ['a', 'e=s', 'target=s', 'verbose']);
my $r := $x.parse(['-a', 'b']);

ok($r.HOW.isa($r, CLIParseResult), 'got the right object type back');
ok($r.arguments()[0] eq 'b', '"b" got classified as argument')
    || say("# arguments: '", pir::join('|', $r.arguments()), "'");
ok($r.options(){'a'} == 1, '-a is an option');

say("alive");

# vim: ft=perl6
