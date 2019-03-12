#!/usr/bin/env perl -w

# Copyright (C) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;

BEGIN {
    unshift @INC, 'lib';
}

use FindBin;
use lib "$FindBin::Bin/lib";
use OpenQA::Utils;
use OpenQA::Test::Utils 'redirect_output';
use Test::More;
use Scalar::Util 'reftype';
use Mojo::File qw(path tempdir tempfile);

is bugurl('bsc#1234'), 'https://bugzilla.suse.com/show_bug.cgi?id=1234', 'bug url is properly expanded';
ok find_bugref('gh#os-autoinst/openQA#1234'), 'github bugref is recognized';
is(find_bugref('bsc#1234 poo#4321'), 'bsc#1234', 'first bugres found');
is_deeply(find_bugrefs('bsc#1234 poo#4321'), ['bsc#1234', 'poo#4321'], 'multiple bugrefs found');
is_deeply(find_bugrefs('bc#1234 #4321'), [], 'no bugrefs found');
is bugurl('gh#os-autoinst/openQA#1234'),                        'https://github.com/os-autoinst/openQA/issues/1234';
is bugurl('poo#1234'),                                          'https://progress.opensuse.org/issues/1234';
is href_to_bugref('https://progress.opensuse.org/issues/1234'), 'poo#1234';
is bugref_to_href('boo#9876'), '<a href="https://bugzilla.opensuse.org/show_bug.cgi?id=9876">boo#9876</a>';
is href_to_bugref('https://github.com/foo/bar/issues/1234'),              'gh#foo/bar#1234';
is href_to_bugref('https://github.com/os-autoinst/os-autoinst/pull/960'), 'gh#os-autoinst/os-autoinst#960',
  'github pull are also transformed same as issues';
is bugref_to_href('gh#foo/bar#1234'), '<a href="https://github.com/foo/bar/issues/1234">gh#foo/bar#1234</a>';
like bugref_to_href('bsc#2345 poo#3456 and more'),
  qr{a href="https://bugzilla.suse.com/show_bug.cgi\?id=2345">bsc\#2345</a> <a href=.*3456.*> and more},
  'bugrefs in text get replaced';
like bugref_to_href('boo#2345,poo#3456'),
  qr{a href="https://bugzilla.opensuse.org/show_bug.cgi\?id=2345">boo\#2345</a>,<a href=.*3456.*},
  'interpunctation is not consumed by href';
is bugref_to_href('jsc#SLE-3275'), '<a href="https://jira.suse.de/browse/SLE-3275">jsc#SLE-3275</a>';
is href_to_bugref('https://jira.suse.de/browse/FOOBAR-1234'), 'jsc#FOOBAR-1234', 'jira tickets url to bugref';

my $t3 = {
    bar => {
        foo => 1,
        baz => [{fish => {boring => 'too'}}, {fish2 => {boring => 'not_really'}}]}};
walker(
    $t3 => sub {
        my ($k, $v, $ks, $what) = @_;
        next if reftype $what eq 'HASH' && exists $what->{_data};
        like $_[0], qr/bar|baz|foo|0|1|fish$|fish2|boring/, "Walked";

        $what->[$k] = {_type => ref $v, _data => $v} if reftype $what eq 'ARRAY';
        $what->{$k} = {_type => ref $v, _data => $v} if reftype $what eq 'HASH';

    });

is_deeply $t3,
  {
    'bar' => {
        '_data' => {
            'baz' => {
                '_data' => [
                    {
                        '_data' => {
                            'fish' => {
                                '_data' => {
                                    'boring' => {
                                        '_data' => 'too',
                                        '_type' => ''
                                    }
                                },
                                '_type' => 'HASH'
                            }
                        },
                        '_type' => 'HASH'
                    },
                    {
                        '_data' => {
                            'fish2' => {
                                '_data' => {
                                    'boring' => {
                                        '_data' => 'not_really',
                                        '_type' => ''
                                    }
                                },
                                '_type' => 'HASH'
                            }
                        },
                        '_type' => 'HASH'
                    }
                ],
                '_type' => 'ARRAY'
            },
            'foo' => {
                '_data' => 1,
                '_type' => ''
            }
        },
        '_type' => 'HASH'
    }};

subtest 'get current version' => sub {
    # Let's check that the version matches our versioning scheme.
    # If it's a git version it should be in the form: git-tag-sha1
    # otherwise is a group of 3 decimals followed by a partial sha1: a.b.c.sha1

    my $changelog_dir  = tempdir;
    my $git_dir        = tempdir;
    my $changelog_file = $changelog_dir->child('public')->make_path->child('Changelog');
    my $refs_file      = $git_dir->child('.git')->make_path->child('packed-refs');
    my $head_file      = $git_dir->child('.git', 'refs', 'heads')->make_path->child('master');
    my $sha_regex      = qr/\b[0-9a-f]{5,40}\b/;

    my $changelog_content = <<'EOT';
-------------------------------------------------------------------
Mon May 08 11:45:15 UTC 2017 - rd-ops-cm@suse.de

- Update to version 4.4.1494239160.9869466:
  * Fix missing space in log debug message (#1307)
  * Register job assets even if one of the assets need to be skipped (#1310)
  * Test whether admin table displays needles which never matched
  * Show needles in admin table which never matched
  * Improve logging in case of upload failure (#1309)
  * Improve product fixtures to prevent dependency warnings
  * Handle wrong/missing job dependencies appropriately
  * clone_job.pl: Print URL of generated job for easy access (#1313)

-------------------------------------------------------------------
Sat Mar 18 20:03:22 UTC 2017 - coolo@suse.com

- bump mojo requirement

-------------------------------------------------------------------
Sat Mar 18 19:31:50 UTC 2017 - rd-ops-cm@suse.de

- Update to version 4.4.1489864450.251306a:
  * Make sure assets in pool are handled correctly
  * Call rsync of tests in a child process and notify webui
  * Move OpenQA::Cache to Worker namespace
  * Trying to make workers.ini more descriptive
  * docs: Add explanation for job priority (#1262)
  * Schedule worker reregistration in case of api-failure
  * Add more logging to job notifications
  * Use host_port when parsing URL
  * Prevent various timer loops
  * Do job cleanup even in case of api failure
EOT

    my $refs_content = <<'EOT';
# pack-refs with: peeled fully-peeled
f8ce111933922cde0c5d11952fbb59b307a700e5 refs/tags/4.0
bb8144fdb128896d0132188c55d298c3905b48aa refs/tags/4.1
87e71451fea9d54927efe9ce3f9e7071fb11e874 refs/tags/4.2
^9953cb8cc89f4e9187f4209035ce2990dbf544cc
ac6dd8d4475f8b7e0d683e64ff49d6d96151fb76 refs/tags/4.3
^11f0541f05d7bbc663ae90d6dedefde8d6f03ff4
EOT

    # Create a valid Changelog and check if result is the expected one
    $changelog_file->spurt($changelog_content);
    is detect_current_version($changelog_dir), '4.4.1494239160.9869466', 'Detect current version from Changelog format';
    like detect_current_version($changelog_dir), qr/(\d+\.\d+\.\d+\.$sha_regex)/, "Version scheme matches";
    $changelog_file->spurt("- Update to version 4.4.1494239160.9869466:\n- Update to version 4.4.1489864450.251306a:");
    is detect_current_version($changelog_dir), '4.4.1494239160.9869466', 'Pick latest version detected in Changelog';

    # Failure detection case for Changelog file
    $changelog_file->spurt("* Do job cleanup even in case of api failure");
    is detect_current_version($changelog_dir), undef, 'Invalid Changelog return no version';
    $changelog_file->spurt("Update to version 3a2.d2d.2ad.9869466:");
    is detect_current_version($changelog_dir), undef, 'Invalid versions in Changelog returns undef';

    # Create a valid Git repository where we can fetch the exact version.
    $head_file->spurt("7223a2408120127ad2d82d71ef1893bbe02ad8aa");
    $refs_file->spurt($refs_content);
    is detect_current_version($git_dir), 'git-4.3-7223a240', 'detect current version from Git repository';
    like detect_current_version($git_dir), qr/(git\-\d+\.\d+\-$sha_regex)/, 'Git version scheme matches';

    # If refs file can't be found or there is no tag present, version should be undef
    unlink($refs_file);
    is detect_current_version($git_dir), undef, "Git ref file missing, version is undef";
    $refs_file->spurt("ac6dd8d4475f8b7e0d683e64ff49d6d96151fb76");
    is detect_current_version($git_dir), undef, "Git ref file shows no tag, version is undef";
};

subtest 'Plugins handling' => sub {

    is path_to_class('foo/bar.pm'),     "foo::bar";
    is path_to_class('foo/bar/baz.pm'), "foo::bar::baz";

    ok grep("OpenQA::Utils", loaded_modules), "Can detect loaded modules";
    ok grep("Test::More",    loaded_modules), "Can detect loaded modules";

    is_deeply [loaded_plugins("OpenQA::Utils", "Test::More")], ["OpenQA::Utils", "Test::More"],
      "Can detect loaded plugins, filtering by namespace";
    ok grep("Test::More", loaded_plugins),
      "loaded_plugins() behave like loaded_modules() when no arguments are supplied";

    my $test_hash = {
        auth => {
            method => "Fake",
            foo    => "bar",
            b      => {bar2 => 2},
        },
        baz => {
            bar => "test"
        }};

    my %reconstructed_hash;
    hashwalker $test_hash => sub {
        my ($key, $value, $keys) = @_;

        my $r_hash = \%reconstructed_hash;
        for (my $i = 0; $i < scalar @$keys; $i++) {
            $r_hash->{$keys->[$i]} //= {};
            $r_hash = $r_hash->{$keys->[$i]} if $i < (scalar @$keys) - 1;
        }

        $r_hash->{$key} = $value if ref $r_hash eq 'HASH';

    };

    is_deeply \%reconstructed_hash, $test_hash, "hashwalker() reconstructed original hash correctly";
};

subtest asset_type_from_setting => sub {
    use OpenQA::Utils 'asset_type_from_setting';
    is asset_type_from_setting('ISO'),              'iso', 'simple from ISO';
    is asset_type_from_setting('UEFI_PFLASH_VARS'), 'hdd', "simple from UEFI_PFLASH_VARS";
    is asset_type_from_setting('UEFI_PFLASH_VARS', 'relative'),  'hdd', "relative from UEFI_PFLASH_VARS";
    is asset_type_from_setting('UEFI_PFLASH_VARS', '/absolute'), '',    "absolute from UEFI_PFLASH_VARS";
};

subtest parse_assets_from_settings => sub {
    use OpenQA::Utils 'parse_assets_from_settings';
    my $settings = {
        ISO   => "foo.iso",
        ISO_2 => "foo_2.iso",
        # this is a trap: shouldn't be treated as an asset
        HDD   => "hdd.qcow2",
        HDD_1 => "hdd_1.qcow2",
        HDD_2 => "hdd_2.qcow2",
        # shouldn't be treated as asset *yet* as it's absolute
        UEFI_PFLASH_VARS => "/absolute/path/uefi_pflash_vars.qcow2",
        # trap
        REPO   => "repo",
        REPO_1 => "repo_1",
        REPO_2 => "repo_2",
        # trap
        ASSET   => "asset.pm",
        ASSET_1 => "asset_1.pm",
        ASSET_2 => "asset_2.pm",
        KERNEL  => "vmlinuz",
        INITRD  => "initrd.img",
    };
    my $assets    = parse_assets_from_settings($settings);
    my $refassets = {
        ISO     => {type => "iso",   name => "foo.iso"},
        ISO_2   => {type => "iso",   name => "foo_2.iso"},
        HDD_1   => {type => "hdd",   name => "hdd_1.qcow2"},
        HDD_2   => {type => "hdd",   name => "hdd_2.qcow2"},
        REPO_1  => {type => "repo",  name => "repo_1"},
        REPO_2  => {type => "repo",  name => "repo_2"},
        ASSET_1 => {type => "other", name => "asset_1.pm"},
        ASSET_2 => {type => "other", name => "asset_2.pm"},
        KERNEL  => {type => "other", name => "vmlinuz"},
        INITRD  => {type => "other", name => "initrd.img"},
    };
    is_deeply $assets, $refassets, "correct with absolute UEFI_PFLASH_VARS";
    # now make this relative: it should now be seen as an asset type
    $settings->{UEFI_PFLASH_VARS}  = "uefi_pflash_vars.qcow2";
    $assets                        = parse_assets_from_settings($settings);
    $refassets->{UEFI_PFLASH_VARS} = {type => "hdd", name => "uefi_pflash_vars.qcow2"};
    is_deeply $assets, $refassets, "correct with relative UEFI_PFLASH_VARS";
};

done_testing;

{
    package foo;
    use Mojo::Base -base;
    sub baz { @_ }
}
