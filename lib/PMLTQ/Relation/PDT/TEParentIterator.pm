package PMLTQ::Relation::PDT::TEParentIterator;

# ABSTRACT: Effective parent relation iterator on t-nodes for PDT like treebanks

use strict;
use warnings;
use base qw(PMLTQ::Relation::SimpleListIterator);
use PMLTQ::Relation {
  name              => 'eparent',
  schema            => 'tdata',
  reversed_relation => 'implementation:echild',
  start_node_type   => 't-node',
  target_node_type  => 't-node',
  iterator_class    => __PACKAGE__,
  iterator_weight   => 2,
  test_code         => q( grep($_ == $end, PMLTQ::Relation::PDT::TGetEParents($start)) ? 1 : 0 ),
};


sub get_node_list {
  my ($self, $node) = @_;
  my $type   = $node->type->get_base_type_name;
  my $fsfile = $self->start_file;
  return [ map [ $_, $fsfile ], PMLTQ::Relation::PDT::TGetEParents($node) ];
}

1;
