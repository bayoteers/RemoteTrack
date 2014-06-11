# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteSync;
use warnings;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::RemoteSync::Util;

our $VERSION = '0.01';

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{schema};

    # Tables for storing the SyncSource objects
    $schema->{sync_source} = {
        FIELDS => [
            id => { TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1 },
            name => { TYPE => 'varchar(64)', NOTNULL => 1, },
            type => { TYPE => 'TINYTEXT', NOTNULL => 1, },
            base_url => { TYPE => 'MEDIUMTEXT', NOTNULL => 1, },
            from_email => { TYPE => 'TINYTEXT', NOTNULL => 0, },
        ],
        INDEXES => [
            sync_source_name_unique_idx => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my ($self, $args) = @_;

}

__PACKAGE__->NAME;
