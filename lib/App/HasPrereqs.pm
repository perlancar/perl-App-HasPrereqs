package App::HasPrereqs;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG qw($log);

use Config::IniFiles;
use Module::Path::More qw(module_path);
use Sort::Versions;

our %SPEC;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(has_prereqs);

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

    my @errs;
    for my $section (grep {
        m!^prereqs (?: \s*/\s* .+)?$!ix} $cfg->Sections) {
      MOD:
        for my $mod ($cfg->Parameters($section)) {
            my $v = $cfg->val($section, $mod);
            $log->infof("Checking prerequisite: %s=%s ...", $mod, $v);
            if ($v eq '0') {
                if ($mod eq 'perl') {
                    # do nothing
                } elsif (!module_path(module => $mod)) {
                    push @errs, {
                        module  => $mod,
                        needed_version => $v,
                        message => "Missing"};
                }
            } else {
                my $iv;
                if ($mod eq 'perl') {
                    $iv = $^V; $iv =~ s/^v//;
                    unless (Sort::Versions::versioncmp($iv, $v) >= 0) {
                        push @errs, {
                            module  => $mod,
                            has_version => $iv,
                            needed_version => $v,
                            message => "Version too old ($iv, needs $v)"};
                    }
                    next MOD;
                }
                my $modp = $mod; $modp =~ s!::!/!g; $modp .= ".pm";
                unless ($INC{$modp} || eval { require $modp; 1 }) {
                    push @errs, {
                        module  => $mod,
                        needed_version => $v,
                        message => "Missing"};
                    next MOD;
                }
                no strict 'refs'; no warnings;
                my $iv = ${"$mod\::VERSION"};
                unless ($iv && Sort::Versions::versioncmp($iv, $v) >= 0) {
                    push @errs, {
                        module  => $mod,
                        has_version => $iv,
                        needed_version => $v,
                        message => "Version too old ($iv, needs $v)"};
                }
            }
        }
    }

    [200, @errs ? "Some prerequisites unmet" : "OK", \@errs,
     {"cmdline.exit_code"=>@errs ? 200:0}];
}

1;
#ABSTRACT:

=head1 SYNOPSIS

 # Use via has-prereqs CLI script

=cut
