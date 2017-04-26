# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteTrack::Params;
use warnings;
use strict;

use Bugzilla::Config::Common qw(check_group);

sub get_param_list {
    return (
        {
            name => 'remotetrack_user',
            type => 't',
            default => '',
            checker => \&_check_user,
        }, {
            name => 'remotetrack_manual_sync',
            type => 'b',
            default => 0,
        }, {
            name => 'remotetrack_status_change_tmpl',
            type => 'l',
            default => 'Our tracking [% terms.bug %] changed status: [% status.0 %] -> [% status.1 %]',
            checker => \&_check_template
        }, {
            name => 'remotetrack_tracking_change_tmpl',
            type => 'l',
            default => "[% tracking ? 'Started' : 'Stopped' %] tracking this." ,
            checker => \&_check_template
        }, {
            name    => 'remotetrack_group',
            type    => 's',
            choices => \&Bugzilla::Config::GroupSecurity::_get_all_group_names,
            default => 'admin',
            checker => \&check_group
        }, {
            name => 'remotetrack_use_queue',
            type => 'b',
            default => 0,
        }, {
            name => 'remotetrack_default_product',
            type => 't',
            default => '',
        }, {
            name => 'remotetrack_default_component',
            type => 't',
            default => '',
        }, {
            name => 'remotetrack_default_version',
            type => 't',
            default => '',
        },
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

sub _check_template {
    my $value = shift;
    if ($value) {
        my $template = Bugzilla->template;
        my $result;
        unless ($template->process(\$value, {}, \$result)) {
            return $template->error;
        }
    }
    return "";
}

1;
