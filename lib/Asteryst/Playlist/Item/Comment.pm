package Asterysk::Playlist::Item::Comment;

use Moose;
extends 'Asterysk::Playlist::Item';

use Carp qw/croak/;

has 'comment' => (
    is => 'rw',
    isa => 'Asterysk::Schema::AsteryskDB::Result::Audiocomment',
    required => 1,
);

sub is_comment    { 1 }

sub subscribe_action { croak "can't call subscribe_action on a comment!" }

sub feed_item {
    my ($self) = @_;
    
    return $self->comment->audiofeeditem;
}


no Moose;
__PACKAGE__->meta->make_immutable;
