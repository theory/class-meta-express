package Class::Meta::Express;

# $Id$

use strict;
use vars qw($VERSION);
use Class::Meta;

$VERSION = '0.03';

my %meta_for;

sub import {
    my $caller = caller;
    no strict 'refs';
    return shift if defined &{"$caller\::meta"};
    *{"$caller\::$_"} = \&{$_} for qw(meta ctor has method build);
    return shift;
}

sub meta {
    my $caller = caller;
    my $key = shift;
    my $args = ref $_[0] eq 'HASH' ? $_[0] : { @_ };
    $args->{key} = $key;
    _export(delete $args->{reexport}, $caller, $args) if $args->{reexport};
    my $meta_class = delete $args->{meta_class} || 'Class::Meta';
    my $def_type   = delete $args->{default_type};
    my $meta = $meta_class->new( package => $caller, %{ $args } );
    $meta_for{$caller} = [ $meta, $def_type ];
    return $meta;
}

sub ctor {
    unshift @_, 'constructor';
    goto &_meth;
}

sub has {
    my ($meta, $def_type) = @{ $meta_for{ scalar caller } };
    unshift @_, $meta, 'name';
    splice @_, 3, 1, %{ $_[3] } if ref $_[3] eq 'HASH';
    splice @_, 3, 0, type => $def_type if $def_type;
    goto $meta->can('add_attribute');
}

sub method {
    unshift @_, 'method';
    goto &_meth;
}

sub build {
    my $meta = delete $meta_for{ my $caller = caller }->[0];
    # Remove exported functions.
    _unimport($caller);

    # Build the class.
    unshift @_, $meta;
    goto $meta->can('build');
}

sub _meth {
    my $method = 'add_' . shift;
    my $meta = $meta_for{ scalar caller }->[0];
    unshift @_, $meta, 'name';
    if (my $ref = ref $_[3]) {
        if ($ref eq 'CODE') {
            splice @_, 3, 0, 'code';
        } else {
            splice @_, 3, 1, %{ $_[3] } if $ref eq 'HASH';
        }
    }
    goto $meta->can($method);
}

sub _unimport {
    my $caller = shift;
    for my $fn (qw(meta ctor has method build)) {
        no strict 'refs';
        my $name = "$caller\::$fn";
        # Copy the current glob contents, excluding CODE.
        my %things = map  { $_ => *{$name}{$_} }
                     grep { defined *{$name}{$_} }
                     qw(SCALAR ARRAY HASH IO FORMAT);
        # Undefine the glob and reinstall the contents.
        undef *{$name};
        *{$name} = $things{$_} for keys %things;
    }
}

sub _export {
    my ($export, $pkg, $args) = @_;
    my @args = map { $_ => $args->{$_} } grep { $args->{$_} }
        qw(meta_class default_type);

    my $meta = !@args ? \&meta : sub {
        splice @_, 1, 0, @args;
        goto &Class::Meta::Express::meta;
    };

    $export = 0 unless ref $export eq 'CODE';

    no strict 'refs';
    *{"$pkg\::import"} = sub {
        my $caller = caller;
        no strict 'refs';
        unless (defined &{"$caller\::meta"}) {
            *{"$caller\::meta"} = $meta;
            *{"$caller\::$_"} = \&{__PACKAGE__ . "::$_"}
                for qw(ctor has method build);
        }
        goto $export if $export;
        return shift;
    };
}

1;
__END__

##############################################################################

=begin comment

Fake-out Module::Build. Delete if it ever changes to support =head1 headers
other than all uppercase.

=head1 NAME

Class::Meta::Express - Concise, expressive creation of Class::Meta classes

=end comment

=head1 Name

Class::Meta::Express - Concise, expressive creation of Class::Meta classes

=head1 Synopsis

  package My::Contact;
  use Class::Meta::Express;

  meta contact => ( default_type => 'string' );

  has 'name';
  has contact => ( required => 1 );

  build;

=head1 Description

This module provides an interface to concisely yet expressively create classes
with L<Class::Meta|Class::Meta>. Although I am of course fond of
L<Class::Meta|Class::Meta>, I've never been overly thrilled with its interface
for creating classes:

  use Class::Meta;

  BEGIN {

      # Create a Class::Meta object for this class.
      my $cm = Class::Meta->new( key => 'thingy' );

      # Add a constructor.
      $cm->add_constructor( name   => 'new' );

      # Add a couple of attributes with generated accessors.
      $cm->add_attribute(
          name     => 'id',
          is       => 'integer',
          required => 1,
      );

      $cm->add_attribute(
          name     => 'name',
          is       => 'string',
          required => 1,
      );

      $cm->add_attribute(
          name    => 'age',
          is      => 'integer',
      );

     # Add a custom method.
      $cm->add_method(
          name => 'chk_pass',
          code => sub { return 'code' },
      );
      $cm->build;
  }

This example is relatively simple; it can get a lot more verbose. But even
still, all of the method calls were annoying. I mean, whoever thought of using
an object oriented interface for I<declaring> a class? (Oh yeah: I did.) I
wasn't alone in wanting a more declarative interface; Curtis Poe, with my
blessing, created L<Class::Meta::Declare|Class::Meta::Declare>, which would
use this syntax to create the same class:

 use Class::Meta::Declare ':all';

 Class::Meta::Declare->new(
     # Create a Class::Meta object for this class.
     meta       => [
         key       => 'thingy',
     ],
     # Add a constructor.
     constructors => [
         new => { }
     ],
     # Add a couple of attributes with generated accessors.
     attributes => [
         id => {
             type    => $TYPE_INTEGER,
             required => 1,
         },
         name => {
             required => 1,
             type     => $TYPE_STRING,
         },
         age => { type => $TYPE_INTEGER, },
     ],
     # Add a custom method.
     methods => [
         chk_pass => {
             code => sub { return 'code' },
         }
     ]
 );

This approach has the advantage of being a bit more concise, and it I<is>
declarative, but I find all of the indentation levels annoying; it's hard for
me to figure out where I am, especially if I have to define a lot of
attributes. And finally, I<everything> is a string with this syntax, except
for those ugly read-only scalars such as C<$TYPE_INTEGER>. So I can't easily
tell where one attribute ends and the next one starts. Bleh.

What I wanted was an interface with the visual distinctiveness of the original
Class::Meta syntax but with the declarative approach and intelligent defaults
of Class::Meta::Declare, while adding B<expressiveness> to the mix. The
solution I've come up with is the use of temporary functions imported into a
class only until the C<build()> function is called:

  use Class::Meta::Express;

  BEGIN {

      # Create a Class::Meta object for this class.
      meta 'thingy';

      # Add a constructor.
      ctor new => ( );

      # Add a couple of attributes with generated accessors.
      has id   => ( is => 'integer', required => 1 );
      has name => ( is => 'string',  required => 1 );
      has age  => ( is => 'integer' );

     # Add a custom method.
      method chk_pass => sub { return 'code' };

      build;
  }

That's much better, isn't it? In fact, we can simplify it even more by setting
a default data type and eliminating the empty lists:

  use Class::Meta::Express;

  BEGIN {

      # Create a Class::Meta object for this class.
      meta thingy => ( default_type => 'integer' );

      # Add a constructor.
      ctor 'new';

      # Add a couple of attributes with generated accessors.
      has id   => ( required => 1 );
      has name => ( is => 'string', required => 1 );
      has 'age';

     # Add a custom method.
      method chk_pass => sub { return 'code' };

      build;
  }

Not bad, eh? I have to be honest: I borrowed the syntax from L<Moose|Moose>.
Thanks for the idea, Stevan!

=head1 Interface

Class::Meta::Express exports the following functions into any package that
C<use>s it. But beware! The functions are temporary! Once you call C<build>,
the functions are all removed from the calling package, thereby avoiding name
space pollution I<and> allowing you to create your own functions or methods,
if you like after C<build>ing the class.

=head2 Functions

=head3 meta

  meta 'thingy';

This function creates and returns the C<Class::Meta|Class::Meta> object that
creates the class. The first argument must be the key to use for the class,
which will be passed as the C<key> parameter to C<< Class::Meta->new >>.
Otherwise, it takes the same parameters as C<< Class::Meta->new >>, as well as
the following additions:

=over

=item meta_class

If you've subclassed Class::Meta and want to use your subclass to define your
classes instead of Class::Meta itself, specify the subclass with this
parameter.

=item default_type

The name of a data type that you'd like to be the default for all attributes
created with C<has> that don't specify their own data types.

=item reexport

Installs an C<import()> method into the calling name space that exports the
express functions. The trick is that, if you've specified values for the
C<meta_class> and/or C<default_type> parameters, they will be used in the
C<meta> function exported by your class! For example:

  package My::Base;
  use Class::Meta::Express;

  meta base => (
       meta_class   => 'My::Meta',
       default_type => 'string',
       reexport     => 1,
  );
  build;

And now other classes can use My::Base instead of Class::Meta::Express and get
the same defaults. Say that you want My::Contact to inherit from My::Base and
use its defaults. Just do this:

  package My::Contact;
  use My::Base;        # Forces import() to be called.
  use base 'My::Base';

  meta 'contact';      # Uses My::Meta
  has  'name'          # Will be a string.
  build;

If you need your own C<import()> method to export stuff, just pass it to the
reexport parameter:

  meta base => (
       meta_class   => 'My::Meta',
       default_type => 'string',
       reexport     => sub { ... },
  );

Class::Meta::Express will do the right thing by shifting execution to your
import method after it finishes its dirty work.

=back

The parameters may be passed as either a list, as above, or as a hash
reference:

  meta base => {
       meta_class   => 'My::Meta',
       default_type => 'string',
       reexport     => 1,
  };

=head3 ctor

  ctor 'new';

Calls C<add_constructor()> on the Class::Meta object created by C<meta>,
passing the first argument as the C<name> parameter. All other arguments can
be any of the parameters supported by C<add_constructor()>:

  ctor new => ( label => 'Foo' );

Or, a if you have Class::Meta 0.53 or later, the second argument can be a code
reference that will be passed as the C<code> parameter to
C<add_constructor()>:

  ctor new => sub { bless {} => shift };

If you want to specify other parameters I<and> the code parameter, do so
explicitly:

  ctor new => (
      label => 'Foo',
      code  => sub { bless {} => shift },
  );

The parameters may be passed as either a list, as above, or as a hash
reference:

  ctor new => {
      label => 'Foo',
      code  => sub { bless {} => shift },
  };

=head3 has

  has name => ( is => 'string' );

Calls C<add_attribute()> on the Class::Meta object created by C<meta>, passing
the first argument as the C<name> parameter. All other arguments can be any of
the parameters supported by C<add_constructor()>, as in the example above. If
the C<default_type> parameter was specified in the call to C<meta>, then the
type (or C<is> if you have Class::Meta 0.53 or later and prefer it) can be
omitted unless you need a different type:

  meta thingy => ( default_type => 'string' );
  has 'name'; # Will be a string.
  has id => ( is => 'integer' );
  # ...

The parameters may be passed as either a list, as above, or as a hash
reference:

  has id => { is => 'integer' };

=head3 method

  method 'say';

Calls C<add_method()> on the Class::Meta object created by C<meta>, passing
the first argument as the C<name> parameter. An optional second argument can
be used to define the method itself (if you have Class::Meta 0.51 or later):

  method say => sub { shift; print @_, $/; }

Otherwise, you'll have to define the method in the class itself (as was
required in Class::Meta 0.50 and earlier). If you want to specify other
parameters to C<add_method()>, just pass them after the method name and
explicitly mix in the C<code> parameter if you need it:

  method say => (
      view => Class::Meta::Protected,
      code => sub { shift; print @_, $/; },
  );

All other arguments can be any of the parameters supported by C<add_meta()>
The parameters may be passed as either a list, as above, or as a hash
reference:

  method say => {
      view => Class::Meta::Protected,
      code => sub { shift; print @_, $/; },
  };

=head3 build

  build;

Removes the C<meta>, C<ctor>, C<has>, C<method>, and C<build> functions from
the calling name space, and then calls C<build()> on the Class::Meta object
created by C<meta>.

=head1 See Also

=over

=item L<Class::Meta|Class::Meta>

This is the module that's actually doing all the work. Class::Meta::Express
just offers an alternative interface for creating new classes with
Class::Meta.

=item L<Class::Meta::Declare|Class::Meta::Declare>

Curtis Poe's declarative inteface to Class::Meta.

=back

=head1 To Do

=over

=item * Make it so that the C<reexport> parameter can work with an C<import>
method that's already installed in a module.

=back

=head1 Bugs

Please send bug reports to <bug-class-meta-express@rt.cpan.org>.

=head1 Author

=begin comment

Fake-out Module::Build. Delete if it ever changes to support =head1 headers
other than all uppercase.

=head1 AUTHOR

=end comment

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2006 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
