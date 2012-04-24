package Asterysk::ContentFetcher;

# this is a module to fetch content from S3 and cache it locally

use Moose;
use namespace::autoclean;

use Asterysk::Config;
use File::DirList;
use LWP::UserAgent;
use Asterysk::Schema::AsteryskDB::Result::Content;

has 'file_extension' => (
    is => 'rw',
    isa => 'Str',
    required => 0,
    lazy => 1,
    builder => 'build_file_extension',
);

# seconds
has 'expire' => (
    is => 'rw',
    isa => 'Int',
);

has 'cache_dir' => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    builder => 'build_cache_dir',
);

sub build_cache_dir {
    my ($self) = @_;
    
    my $config = Asterysk::Config->get;
    return $config->{agi}{content_cache_directory}
        or die '$config->{agi}{content_cache_directory} is not defined';
}

sub build_file_extension {
    my ($self) = @_;
    
    my $config = Asterysk::Config->get;
    return $config->{agi}{sound_file_extension}
        or die '$config->{agi}{sound_file_extension} is not defined';
}

# returns undef if false, path to cached file if true
sub is_content_cached {
    my ($self, $content_id) = @_;
    
    my $path = $self->get_content_cache_path($content_id);
    return -e $path ? $path : undef;
}

sub get_content_cache_path {
    my ($self, $content_id) = @_;
    
    my $cache_dir = $self->cache_dir;
    my $file_name = $self->_get_content_file_name($content_id);
    my $path = $cache_dir . '/' . $file_name;
    return $path;
}

# takes a content object, returns path on disk
# in array context returns ($path, $was_cached)
sub fetch_content {
    my ($self, $content_id) = @_;
    
    my $content = new Asterysk::Schema::AsteryskDB::Result::Content->new({ id => $content_id });
    
    my $cache_dir = $self->cache_dir;
    
    if (! -e $cache_dir) {
        # make cache directory
        unless (mkdir $cache_dir) {
            die "unable to create cache directory $cache_dir: $!";
        }
    }
    
    if (! -d $cache_dir || ! -w $cache_dir) {
        die "cannot write to directory $cache_dir";
    }

    if (int(rand(100)) == 1) {
        # every now and then prune old files
        $self->_prune;
    }
    
    my $path = $self->get_content_cache_path($content_id);
    
    if (-e $path) {
        # file is cached, hurray
        return wantarray ? ($path, 1) : $path;
    }
    
    my $url = $content->s3_url;
    my $ua = new LWP::UserAgent();
    my $res = $ua->get($url, ':content_file' => $path);
    
    unless ($res->is_success) {
        die "req failed for $url: " . $res->status_line;
    }
    
    return wantarray ? ($path, 0) : $path;
}

# expects listref of content ids to preserve
sub delete_all_except {
    my ($self, $ids_ref) = @_;
    
    my @ids = @$ids_ref;
    
    my $files = File::DirList::list($self->cache_dir, 'Dc', 1, 1);
    foreach my $f (@$files) {
        next if $f->[14]; # skip dirs
        
        my @f = @$f;
        my $path = $f[13];  # path

        my ($content_id) = $path =~ m/content_(\d+)\.\w+$/;
        unless ($content_id) {
            print "Error: found odd file in " . $self->cache_dir . ": $path\n";
            
            # pause so we don't end up doing a zillion disk accesses if everything is a failure
            select undef, undef, undef, 0.5;
            
            next;
        }
        
        # delete file if it's not in the list of content ids passed in
        if (! grep { $_ == $content_id } @ids) {
            unlink $self->cache_dir . '/' . $path;
        }
    }
}

# delete expired cache files
sub _prune {
    my ($self) = @_;

    return unless $self->expire;
    
    # get list of files sorted by create time
    my $files = File::DirList::list($self->cache_dir, 'Dc', 1, 1);
    foreach my $f (@$files) {
        next if $f->[14]; # skip dirs
        
        my @f = @$f;
        my $path = $f[13];  # path

        my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
            $atime,$mtime,$ctime,$blksize,$blocks)
            = (@f[0..12]);  # stat

        next unless $ctime;

        if (time() - $ctime > $self->expire) {
            unlink $self->cache_dir . '/' . $path;
        }
    }
}

# should be sequential so it's easy to purge old files
sub _get_content_file_name {
    my ($self, $content_id) = @_;
    
    return "content_${content_id}." . $self->file_extension;
}

no Moose;
__PACKAGE__->meta->make_immutable;
