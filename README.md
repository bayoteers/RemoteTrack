Bugzilla Remote Sync Extension
==============================

Goal of this extension is to provide a way to link bugs in remote Bugzilla
instances (and possibly other bug tracking systems) and automatically sync some
changes between the local and remote bug.

Target is to help working more directly with upstream projects and still allow
tracking time, dependencies, etc. in your own Bugzilla instance.

NOTE: This extension is still highly experimental.


Installation
------------

1. Put extension files in

        extensions/RemoteTrack

2. Run checksetup.pl

3. Restart your webserver if needed (for exmple when running under mod_perl)


Configuration
-------------

1. Create user which will be used for the bug comments etc.
2. Set the user and other options in Administration > Parameters > RemoteTrack
3. Add remote tracking source in Administration > RemoteTrack Sources

Currently remote item change notifications can be only received via email.
Mainly because only supported remote system is Bugzilla, and by default it does
not have any other way to notify about bug changes.

For this you need to have a user account on the remote bugzilla instance, and
have that user set as global watcher to receive email notifications on all bug
changes and new bugs.

To handle the email notifications, your Bugzilla installation needs to be able
to receive emails sent to the tracking user, and you need to setup the mail
to pipe the messages to the handler script. For example in procmail something
like this should work:

     :0:
     * ^TObug-tracker@example.com
     | cd <BZ_ROOT>; ./extensions/RemoteTrack/email_in_sync.pl 2>>email_in_sync.err.log

Where `<BZ_ROOT>` is the path to Bugzilla install dir.

Or use any other way to pipe the incoming messages to the `email_in_sync.pl`.
It needs to be executed from the Bugzilla root directory, or you can pass it
the bugzilla root with the `-b` commandline option.
