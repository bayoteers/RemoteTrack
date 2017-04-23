# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2015-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteTrack::Job::PostChanges;
use strict;
use warnings;

use Bugzilla::Bug;
use Bugzilla::Extension::RemoteTrack::Source;

BEGIN { eval "use base qw(TheSchwartz::Worker)"; }

# The longest we expect a job to possibly take, in seconds.
use constant grab_for => 60;
# No need to try that many times
use constant max_retries => 10;

use constant retry_delay => 300;

sub work {
    my ($class, $job) = @_;
    my $url = $job->arg->{url};
    my $bug_id = $job->arg->{bug_id};
    my $changes = $job->arg->{changes};
    my $bug = Bugzilla::Bug->new($bug_id);

    my $success = 0;
    my $source = Bugzilla::Extension::RemoteTrack::Source->get_for_url($url);
    if (defined $source) {
        $success = eval {$source->post_changes($url, $bug, $changes)};
    }

    if (!$success) {
        $job->failed($@);
        undef $@;
    } else {
        $job->completed;
    }
}

1;
