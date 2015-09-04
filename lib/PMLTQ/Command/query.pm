package PMLTQ::Command::query;
use PMLTQ::Command;
use Cwd;
use File::Spec;

use Treex::PML;
use Treex::PML::Instance;
use Treex::PML::Schema;
use Getopt::Long qw(GetOptionsFromArray);
use PMLTQ::Common ':tredmacro';
use HTTP::Request::Common;
use LWP::UserAgent;
use File::Temp;
use Encode;


sub run {
  my $self = shift;
  my @args = @_
  my %opts;
  GetOptionsFromArray(\@args, \%opts, 
  'debug|D',
  'server|s=s',
  'command|c=s',

  'ntred|N',
  'jtred|J',
  'btred|B',
  'sql|S',
  'shared-dir|d=s',
  'keep-tmp-files',
  'filelist|l=s',

  'username=s',
  'password=s',
  'auth-id=s',

  'pmltq-extension-dir|X=s',

        'stdin',
  'query|Q=s',
        'query-id|i=s',
  'query-file|f=s',
        'query-pml-file|p=s',
  'filters|F=s',
  'no-filters',

  'netgraph-query|G=s',

  'print-servers|P',
  'config-file|c=s',

  'node-types|n',
  'relations|r',

  'limit|L=i',
  'timeout|t=i',

  'quiet|q',
  'help|h=s@',
  'usage|u',
        'version|V',
  'man' ) || die "invalid options";
  Treex::PML::AddResourcePath(
       PMLTQ->resources_dir,
       File::Spec->catfile(${FindBin::RealBin},'config'),
       $ENV{HOME}.'/.tred.d'
      );
  Treex::PML::AddBackends(qw(Storable PMLBackend PMLTransformBackend));

  if ($opts{stdin}) {
    local $/;
    $opts{query} = <STDIN>;
  }

  $opts{$1}=1 if defined($opts{server}) and $opts{server}=~s{^[nbj]tred://}{};
  my $extension_dir =
    $opts{'pmltq-extension-dir'} ||
    File::Spec->catfile($ENV{HOME},'.tred.d','extensions', 'pmltq');
  Treex::PML::AddResourcePath(File::Spec->catfile($extension_dir,'resources'));

  if ($opts{ntred}) {
    ntred_search();
  } elsif ($opts{jtred}) {
    jtred_search();
  } elsif ($opts{btred}) {
    btred_search();
  } else {
    pmltq_http_search();
  }
}







my %auth;
sub pmltq_http_search {
  my $query;
  if ($opts{query} and !@ARGV) {
    $query = $opts{query};
  } elsif (!$query and @ARGV) {
    $query=join ' ',@ARGV;
  } elsif ($opts{'query-pml-file'}) {
    my $query_file = Treex::PML::Factory->createDocumentFromFile($opts{'query-pml-file'});
    die "Failed to open PML query file $opts{'query-pml-file'}: $Treex::PML::FSError\n" if $Treex::PML::FSError or !$query_file or !$query_file->trees;
    $query = first {
      !$opts{'query-id'} or $_->{id} and $_->{id} eq $opts{'query-id'}
    } $query_file->trees;
    die "Didn't find query $opts{'query-id'} in query file $opts{'query-pml-file'}!" unless $query;
    $query = encode('UTF-8',PMLTQ::Common::as_text($query));
  } elsif ($opts{'query-file'}) {
    local $/;
    open my $fh, $opts{'query-file'}
      or die "Cannot open query file '$opts{'query-file'}': $!";
    $query = <$fh>;
    if ($opts{'query-id'}) {
      $query=~s/#\s*==\s*query:\s*\Q$opts{'query-id'}\E\s* ==(.*?)(?:#\s*==\s*query:\s*\w+\s*==.*|$)/$1/s;
    }
  } elsif (!$opts{'node-types'} and !$opts{'relations'} and !$opts{'print-servers'}) {
    pod2usage(-msg => 'pmltq');
    exit 1;
  }
  if (!$opts{'query-pml-file'} and $opts{'netgraph-query'}) {
    require PMLTQ::NG2PMLTQ;
    $query = PMLTQ::NG2PMLTQ::ng2pmltq($query,{type=>$opts{'netgraph-query'}});
  }

  if (!$opts{'node-types'} and !$opts{'relations'} and !$opts{'print-servers'}) {
    die "Query is empty!" unless $query;

    my $filters = $opts{'filters'};
    if ($filters and $filters=~/\S/) {
      $filters='>> '.$filters unless $filters =~ /^\s*>>/;
      $query .= $filters;
    }
  }

  $opts{'config-file'} ||= Treex::PML::FindInResources('treebase.conf');
  if ($opts{debug}) {
    print STDERR "Reading configuration from $opts{'config-file'}\n";
  }
  my $configs = (-f $opts{'config-file'}) ?
      Treex::PML::Factory->createPMLInstance({ filename=>$opts{'config-file'} })->get_root->{configurations}
  : undef;

  my $id = $opts{'server'};
  $id ||= 'default' unless $opts{'print-servers'};
  my ($conf,$type) = $id ? get_server_conf($configs,$id) : ();
  %auth = (
    username => $opts{username},
    password => $opts{password},
   );
  if ($opts{'auth-id'}) {
    my ($auth) = get_server_conf($configs,$opts{'auth-id'});
    if ($auth) {
      $auth{$_} ||= $auth->{$_} for qw(username password);
    } else {
      die "Didn't find auth-id configuration: $opts{'auth-id'}\n";
    }
  }
  if ($conf) {
    $auth{$_} ||= $conf->{$_} for qw(username password);
  }


  if ($opts{'print-servers'}) {
    if ($opts{'server'}) {
      unless ($type eq 'http') {
  die "Cannot query available services on a $type server";
      }
      my $result='';
      http_search($conf->{url},$query,{ other=>1,
          callback => sub { $result.=$_[0] },
          debug=>$opts{debug},
          %auth,
               });
      my @services = split /\n/,$result;
      for my $srv (@services) {
  my %srv = map { split(':',$_,2) } split /\t/, $srv;
  print $srv{id},"\t",$srv{service},"\t",$srv{title},"\n";
      }
      exit;
    }
    my @types = qw(dbi http);
    my %columns = (
      dbi => [qw(driver host port database username sources)],
      http => [qw(url username cached_description/title)],
     );
    my %configs = (
      map { my $type = $_; ($_ =>[map $_->value, grep { $_->name eq $type } SeqV($configs)]) }
  @types
       );
    for my $type (@types) {
      my $confs = $configs{$type};
      if (@$confs) {
  print uc($type)." configurations:\n";
  print (("-"x60)."\n");
  no warnings;
  for my $c (@$confs) {
    print $c->{id}.": ".(join(", ", map "$_->[0]=$_->[1]",
            grep length($_->[1]),
            map [m{/(.*)} ? $1 : $_,Treex::PML::Instance::get_data($c,$_)], @{$columns{$type}})."\n");
  }
      }
      print "\n";
    }
    exit;
  }



  print STDERR $query,"\n" if $opts{debug};
  
  
  
  if ($type eq 'http') {
    http_search($conf->{url},$query,{ 'node-types'=>$opts{'node-types'},
              'relations'=>$opts{'relations'},
              debug=>$opts{debug},
              %auth
             });
  } else {
    require PMLTQ::SQLEvaluator;
    my $evaluator = PMLTQ::SQLEvaluator->new(undef,{connect => $conf, debug=>$opts{debug},
               %auth
              });
    $evaluator->connect();
    if ($opts{'node-types'}) {
      print join "\n", @{$evaluator->get_node_types};
    } elsif ($opts{'relations'}) {
      print join "\n", @{$evaluator->get_specific_relations};
    } else {
      search($evaluator,$query);
    }
    $evaluator->{dbi}->disconnect() if $evaluator->{dbi};
  }
}

sub get_server_conf {
  my ($configs,$id)=@_;
  my ($conf,$type);
  if ($id =~ /^http:/) {
    $type = 'http';
    $conf = {url => $id};
  } else {
    my $conf_el = first { $_->value->{id} eq $id }  SeqV($configs);
    die "Didn't find server configuration named '$id'!\nUse $0 --print-servers and then $0 --server <config-id|URL>\n"
      unless $conf_el;
    $conf = $conf_el->value;
    $type = $conf_el->name;
  }
  return ($conf,$type);
}

sub http_search {
  my ($url,$query,$opts)=@_;
  $opts||={};
  my $tmp = File::Temp->new( TEMPLATE => 'pmltq_XXXXX',
           TMPDIR => 1,
           UNLINK => 1,
           SUFFIX => '.txt' );
  my $ua = LWP::UserAgent->new;
  $ua->credentials(URI->new($url)->host_port,'PMLTQ',
       $auth{username}, $auth{password})
    if $opts->{username};
  $ua->agent("PMLTQ/1.0 ");
  $url.='/' unless $url=~m{^https?://.+/};
  if ($opts->{'node-types'}) {
    $url = qq{${url}nodetypes};
    $query = '';
  } elsif ($opts->{'relations'}) {
    $url = qq{${url}relations};
    $query = '';
  } elsif ($opts->{'other'}) {
    $url = qq{${url}other};
    $query = '';
  } else {
    $url = qq{${url}query};
  }
  $ua->timeout($opts{timeout}+2) if $opts{timeout};
  my $q = $query; Encode::_utf8_off($q);
  binmode STDOUT;
  my $sub = $opts->{callback} || sub { print $_[0] };
  my $res = $ua->request(POST($url, [
      query => $q,
      format => 'text',
      limit => $opts{limit},
      row_limit => $opts{limit},
      timeout => $opts{timeout},
     ]),$sub ,1024*8 );
  unless ($res->is_success) {
    die $res->status_line."\n".$res->content."\n";
  }
}

sub search {
  my ($evaluator,$query)=@_;
  my $results;
  eval {
    $evaluator->prepare_query($query); # count=>1
    $results = $evaluator->run({
      node_limit => $opts{limit},
      row_limit => $opts{limit},
      timeout => $opts{timeout},
      timeout_callback => sub {
  print STDERR "Evaluation of query timed out\n";
  exit 2;
      },
    });
  };
  warn $@ if $@;
  if ($results) {
    for my $r (@$results) {
      print join("\t",@$r)."\n";
    }
    print STDERR $#$results+1," result(s)\n" unless $opts{quiet};
  }
}

sub quote_cmdline {
  my $quoted;
  join ' ', map {
    my $arg = $_;
    $arg =~ s{'}{'\\''}g;
    qq{'$arg'}
  } @_;
}

sub ntred_search {
  my ($host,$port)= $opts{server} ? split(/:/,$opts{server}) : ();
  my $command = $opts{command} || 'ntred';

  my $shared_dir=File::Spec->rel2abs($opts{'shared-dir'} || '.');
  my $filter_file="$shared_dir/pmltq_ntred_filter.$$.pl";

  my @script_flags=('--filter-code-out', $filter_file);
  foreach (qw(query query-id query-file query-pml-file filters netgraph-query)) {
    push @script_flags, '--'.$_, (/file/ ? File::Spec->rel2abs($opts{$_}) : $opts{$_})
      if defined($opts{$_}) and length($opts{$_});
  }

  $command .= ' '.quote_cmdline(
    ((defined($host) and length($host)) ? ('--hub',$host) : ()),
    ((defined($port) and length($port)) ? ('--port',$port) : ()),
    '-q',
    '-I', File::Spec->catfile($extension_dir,qw(contrib pmltq pmltq.ntred)),
    ($opts{filelist} ? ('-l', File::Spec->rel2abs($opts{filelist})) : (@ARGV ? ('-L', '--', @ARGV) : ())),
    '--', @script_flags
  );
  open(my $pipe, $command.' | ') || die "Failed to start ntred client: $!";
  apply_filter($pipe, $filter_file);
  close($pipe);
  unlink $filter_file if -f $filter_file and !$opts{'keep-tmp-files'};
}

sub jtred_search {
  my $command = $opts{command} || 'jtred';

  my $jobname="pmltq_jtred_$$";
  if ($opts{server}) {
    $jobname.="-".$ENV{HOSTNAME};
  }

  my $shared_dir=File::Spec->rel2abs($opts{'shared-dir'} || '.');
  my $filter_file="$shared_dir/$jobname.pl";
  my $filelist;
  if ($opts{filelist}) {
    my ($vol,$dir) = File::Spec->splitpath($opts{filelist});
    my $base = File::Spec->catpath($vol,$dir);
    open my $fh, '<', $opts{filelist} or die "Cannot open filelist $opts{filelist}: $!";
    $filelist = "$shared_dir/$jobname.fl";
    open my $out_fh, '>', $filelist or die "Cannot create temporary filelist $filelist: $!";
    print STDERR "Resolving filelist files to $base...\n" unless $opts{quiet};
    while(<$fh>) {
      chomp;
      print $out_fh File::Spec->rel2abs($_,$base),"\n";
    }
    print STDERR "done.\n" unless $opts{quiet};
    close $fh;
    close $out_fh;
  }
  my @script_flags=('--filter-code-out', $filter_file);
  foreach (qw(query query-id query-file query-pml-file filters netgraph-query)) {
    push @script_flags, '--'.$_, (/file/ ? File::Spec->rel2abs($opts{$_}) : $opts{$_})
      if defined($opts{$_}) and length($opts{$_});
  }
  my @command = (
    $command,
    ($opts{'shared-dir'} ? ('-jw', $shared_dir) : ()),
    '-jn', $jobname,
    ($opts{quiet} ? '-jq' : ()),
    ($filelist ? ('-l', $filelist) : @ARGV),
    '-jb',
    '-q',
    '-I', File::Spec->catfile($extension_dir,qw(contrib pmltq pmltq.ntred)),
    '-o',  @script_flags, '--'
  );
  my $pipe;
  if ($opts{server}) {
    my $cwd = quote_cmdline(getcwd());
    open($pipe, '-|', 'ssh', $opts{server}, <<"SCRIPT".quote_cmdline(@command))
if [ -f ~/.bash_profile ]; then
   . ~/.bash_profile 2>/dev/null 1>&2
elif [ -f ~/.profile ]; then
   . ~/.profile 2>/dev/null 1>&2
fi
cd $cwd;
SCRIPT
      || die "Failed to start jtred on host $opts{server} over ssh: $!"
  } else {
    open($pipe, '-|',@command)
      || die "Failed to start jtred: $!";
  }
  apply_filter($pipe, $filter_file);
  close($pipe);
  unlink $filter_file if -f $filter_file and !$opts{'keep-tmp-files'};
  unlink $filelist if $filelist and !$opts{'keep-tmp-files'};
}

sub btred_search {
  my $command = $opts{command} || 'btred';

  my $jobname="pmltq_btred_$$";
  if ($opts{server}) {
    $jobname.="-".$ENV{HOSTNAME};
  }

  my $shared_dir=File::Spec->rel2abs($opts{'shared-dir'} || '.');
  my $filter_file="$shared_dir/$jobname.pl";

  my @script_flags=('--filter-code-out', $filter_file);
  foreach (qw(query query-id query-file query-pml-file filters netgraph-query)) {
    push @script_flags, '--'.$_, (/file/ ? File::Spec->rel2abs($opts{$_}) : $opts{$_})
      if defined($opts{$_}) and length($opts{$_});
  }
  for (qw(node-types relations)) {
    if ($opts{$_}) {
      push @script_flags, '--info', $_;
      last;
    }
  }

  $command .= ' '.quote_cmdline(
    ($opts{quiet} ? '-Q' : '-q'),
    '-I', File::Spec->catfile($extension_dir,qw(contrib pmltq pmltq.ntred)),
    '-o', '--apply-filters', @script_flags, '--',
    ($opts{filelist} ? ('-l', $opts{filelist}) : @ARGV),
  );
  if ($opts{server}) {
    my $cwd = quote_cmdline(getcwd());
    system('ssh', $opts{server}, <<"SCRIPT");
if [ -f ~/.bash_profile ]; then
   . ~/.bash_profile
elif [ -f ~/.profile ]; then
   . ~/.profile;
fi
cd $cwd
$command
SCRIPT
  } else {
    system($command);
  }
  unlink $filter_file if -f $filter_file and !$opts{'keep-tmp-files'};
}


sub round {
  my ($value, $precision) = @_;
  my $rounding = ($value >= 0 ? 0.5 : -0.5);
  my $decimalscale = 10**int($precision || 0);
  my $scaledvalue = int($value * $decimalscale + $rounding);
  return $scaledvalue / $decimalscale;
}

sub trunc {
  my ($self, $num, $digits) = @_;
  $digits = int $digits;
  my $decimalscale = 10**abs($digits);
  if ($digits >= 0) {
    return int($num * $decimalscale) / $decimalscale;
  } else {
    return int($num / $decimalscale) * $decimalscale;
  }
}

sub apply_filter {
  my ($input, $filter_file)=@_;
  my $filters;
  my $filter;
  my $first = 1;
  use POSIX qw(ceil floor);

  if ($opts{'no-filters'}) {
    print while (<$input>);
    return;
  }

  my $output_filter = {
    init => sub { },
    process_row => sub {
      my ($self,$row)=@_;
      print(join("\t",@$row)."\n");
    },
    finish => sub { }
   };

  while (<$input>) {
    chomp;
    unless ($filter) {
      if (-f $filter_file and -s $filter_file) {
  open my $fh, "<", $filter_file or
    die "Cannot open $filter_file: $!";
  my $filter_code;
  {
    local $/;
    $filter_code = <$fh>;
  }
  eval "use utf8;\n".$filter_code;
  if ($@) {
    print STDERR $filter_code;
    print STDERR "\n";
    die "Running filter $filter_file failed!";
  }
  my @filters = map {
    my @local_filters = map eval, @{$_->{local_filters_code}};
    my $sub = eval($_->{code});
    die $@ if $@;
    $sub
  } @$filters;

  # connect filters
  my $prev;
  for my $filter (@filters) {
    $prev->{output}=$filter if $prev;
    $prev = $filter;
  }
  if ($prev) {
    $prev->{output} = $output_filter;
  }
  $filter = $filters[0] || die "First filter is empty!";
  $filter->{init}->($filter);
      } else {
  $filter = $output_filter;
      }
    }
    $filter->{process_row}->($filter,[split /\t/,$_]);
  }
  $filter->{finish}->($filter) if $filter;
}


1;