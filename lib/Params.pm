# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteSync::Params;
use warnings;
use strict;

sub get_param_list {
    return (
        {
            name => 'remotesync_user',
            type => 't',
            default => '',
            checker => \&_check_user,
        }, {
            name => 'remotesync_manual_sync',
            type => 'b',
            default => 0,
        }
    );
}

sub _check_user {
    my $value = shift;
    if ($value) {
        eval {Bugzilla::User->check($value);};
        return $@ || "";
    }
    return "";
}

1;
