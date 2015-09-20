#!/usr/bin/perl -Ilib -I../lib
# Run this like so: `perl test_query_sql.t'
#   Matyas Kopp <matyas.kopp@gmail.com>     2015/09/19 20:30:00

use Test::More;
plan skip_all => 'set TEST_QUERY to enable this test (developer only!)'
  unless $ENV{TEST_QUERY};

use Capture::Tiny ':all';
use PMLTQ::Commands;
use File::Basename;
use FindBin qw($RealBin);
use lib ($RealBin.'/../lib', ## PMLTQ
	 $RealBin.'/libs', 
	);
use DBI;


my @cmds = qw/initdb verify help convert delete load man/;
my $conf_file = File::Spec->catfile($FindBin::RealBin, 'treebanks','pdt20_sample_small', 'config.yml');

subtest 'command' => \&command;
subtest 'help' => \&help;
subtest 'convert' => \&convert;
plan skip_all =>  'SKIPPING THE REST OF TESTS' unless subtest 'test database connection' => \&dbconect;
subtest 'initdb' => \&initdb;
subtest 'load' => \&load;
subtest 'verify' => \&verify;
subtest 'delete' => \&del;

done_testing();

sub command {
  undef $@;
  capture_merged {eval {PMLTQ::Commands->run("help")}};
  ok(! $@, "calling command");
  eval {PMLTQ::Commands->run("UNKNOWN_COMMAND")};
  ok($@, "calling unknown command");
}

sub help {
  for my $c (@cmds) {
    my @args = ("help", $c, 1);
    undef $@;
    my $h = capture_merged {eval {PMLTQ::Commands->run(@args)}};
    ok(! $@, "calling help for $c command");
    isnt($h,'',"$c help is not empty");
  }
  my $c = "UNKNOWN_COMMAND";
  my @args = ("help", "$c", 1);
  undef $@;
  my $h = capture_merged {eval {PMLTQ::Commands->run(@args)}};
  ok($@, "calling help for $c command");
  like($h, qr/unknown command/i,"$c help contains warning 'unknown command'");

  $h = capture_merged {eval {PMLTQ::Commands->run("help")}};
  undef $@;
  ok(! $@, "calling help without parameters");
  isnt($h, '',"help is not empty");
   
}




sub convert {
  undef $@;
  $h = capture_merged {eval {PMLTQ::Commands->run("convert",$conf_file,"TMPTMP")}};
  ok(! $@, "conversion ok");
  print STDERR $@ if $@;

## TODO absolute/relative paths
## checking conversion (basic)
}


sub dbconect {
  my $config = PMLTQ::Command::load_config($conf_file);
  my $dbh = DBI->connect("DBI:".$config->{db}->{driver}.":dbname=postgres;host=".$config->{db}->{host}.";port=".$config->{db}->{port}, 
    $config->{db}->{user}, 
    $config->{db}->{password}, 
    { RaiseError => 0, PrintError => 1, mysql_enable_utf8 => 1 });
  unless($dbh) {
    fail("database connection failed");
    return;
  }
  pass("succesfully connected to database");
  $dbh->disconnect();
  return 1;
}

sub initdb {
  $h = capture_merged {eval {PMLTQ::Commands->run("initdb",$conf_file)}};
  ok(! $@, "initdb ok");
  print STDERR $@ if $@;  
  pass('initdb TODO');
}
sub load {
  pass('load TODO');
}
sub del {
  pass('delete TODO');
}

sub verify {

  pass('verify TODO');
}















