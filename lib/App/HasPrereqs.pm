package App::HasPrereqs;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use Config::IniFiles;
use Module::Path qw(module_path);
use Sort::Versions;

our %SPEC;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(has_prereqs);

# VERSION

$SPEC{has_prereqs} = {
    v => 1.1,
    summary =>
        'Check whether your Perl installation has prerequisites in dist.ini',
    args => {
        library => {
            schema => ['array*' => {of => 'str*'}],
            summary => 'Add directory to @INC',
            cmdline_aliases => {I => {}},
        },
    },
};
sub has_prereqs {

    my %args = @_;

    my $libs = $args{library} // [];
    local @INC = @INC;
    unshift @INC, $_ for @$libs;

    (-f "dist.ini")
        or return [412, "No dist.ini found, ".
                       "is your dist managed by Dist::Zilla?"];

    my $cfg = Config::IniFiles->new(-file => "dist.ini", -fallback => "ALL");
    $cfg or return [
        500, "Can't open dist.ini: ".join(", ", @Config::IniFiles::errors)];

    my $err;
    for my $section (grep {
        m!^prereqs (?: \s*/\s* .+)?$!ix} $cfg->Sections) {
      MOD:
        for my $mod ($cfg->Parameters($section)) {
            my $v = $cfg->val($section, $mod);
            $log->infof("Checking prerequisite: %s=%s ...", $mod, $v);
            if ($v eq '0') {
                if ($mod eq 'perl') {
                    # do nothing
                } elsif (!module_path($mod)) {
                    $err++;
                    $log->errorf("Missing prerequisite: %s", $mod);
                }
            } else {
                my $iv;
                if ($mod eq 'perl') {
                    $iv = $^V; $iv =~ s/^v//;
                    unless (Sort::Versions::versioncmp($iv, $v) >= 0) {
                        $err++;
                        $log->errorf("Perl version too old (%s, needs %s)",
                                     $iv, $v);
                    }
                    next MOD;
                }
                my $modp = $mod; $modp =~ s!::!/!g; $modp .= ".pm";
                unless ($INC{$modp} || eval { require $modp; 1 }) {
                    $err++;
                    $log->errorf("Missing prerequisite: %s", $mod);
                    next MOD;
                }
                no strict 'refs'; no warnings;
                my $iv = ${"$mod\::VERSION"};
                unless ($iv && Sort::Versions::versioncmp($iv, $v) >= 0) {
                    $err++;
                    $log->errorf("Installed version too old: %s (%s, needs %s)",
                                 $mod, $iv, $v);
                }
            }
        }
    }

    $err ?
        [500, "Some prerequisites unmet", undef,
         {"cmdline.display_result"=>0}] :
            [200, "OK"];
}

1;
#ABSTRACT: Check whether your Perl installation has prerequisites in dist.ini

=head1 SYNOPSIS

 # Use via has-prereqs CLI script

=cut
