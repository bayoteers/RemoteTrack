# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteSync::Pages;
use warnings;
use strict;

use Bugzilla;

use Bugzilla::Extension::RemoteSync::Source;

sub source_html {
	my $vars = shift;

	ThrowUserError('auth_failure', {
            group => 'admin',
            action => 'access'
        }) unless Bugzilla->user->in_group('admin');

	my $input = Bugzilla->input_params;
	my $source_id = delete $input->{source_id};
	my $action = delete $input->{action} || '';
	my $source;
	if ($source_id) {
		$source = Bugzilla::Extension::RemoteSync::Source->check({id=>$source_id});
	}
	if ($action eq 'save') {
		my $params = {
			name => delete $input->{name},
		};
		my %options;
		for my $key (keys %$input) {
			($key) = $key =~ /option_(.*)/;
			next unless $key;
			$options{$key} = delete $input->{"option_$key"};
		}
		$params->{options} = \%options;

		if ($source) {
			$source->set_all($params);
			$source->update();
		} else {
			$params->{class} = delete $input->{class};
			$source = Bugzilla::Extension::RemoteSync::Source->create($params);
		}
	} elsif ($action eq 'delete' && defined $source) {
		$source->remove_from_db();
		$source = undef;
	} else {
		$vars->{source} = $source;
	}
	$vars->{action} = $action;
	$vars->{source_classes} = Bugzilla::Extension::RemoteSync::Source->CLASSES;
	$vars->{sources} = [Bugzilla::Extension::RemoteSync::Source->get_all()];
}

1;
