package PMLTQ::PML2BASE::PDT::MakeTable;

# ABSTRACT: Make tables for PDT user defined relations

use strict;
use warnings;

sub mk_eparent_table {
  my ($schema,$desc,$fh)=@_;
  my $name = $schema->get_root_name;
  my @tables;
  my $table_name = PMLTQ::PML2BASE::rename_type($name.'__#eparents');
  @tables = ($table_name);
  unless ($PMLTQ::PML2BASE::opts{'no-schema'}) {
    my $node_type;
    $node_type = 'a-data' if $name =~ m/adata/;
    $node_type = 't-data' if $name =~ m/tdata/;
    if ($node_type) {
      my $node_table  = PMLTQ::PML2BASE::rename_type($node_type);
      $fh->{'#INIT_SQL'}->print(<<"EOF");
INSERT INTO "#PML_USR_REL" VALUES('eparent','echild','${node_type}','${node_type}','${table_name}');
EOF
      $fh->{'#DELETE_SQL'}->print(<<"EOF");
DELETE FROM "#PML_USR_REL" WHERE "tbl"='${table_name}';
EOF
    }
  }
  for my $table (@tables) {
    $desc->{$table} = {
      table => $table,
      colspec => [
        ['#idx','INT'],
        ['#value','INT'],
      ],
      index => ["#idx","#value"]
    };
    open $fh->{$table},'>',PMLTQ::PML2BASE::get_full_path(PMLTQ::PML2BASE::to_filename($table));
  }
}

sub mk_extra_tables {
  mk_eparent_table(@_) unless $PMLTQ::PML2BASE::opts{'no-eparents'};
}

1;