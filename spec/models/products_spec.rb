require 'spec_helper'

module Spree
  describe Spree::Product do
    let(:a_product) { create(:product) }
    let(:another_product) { create(:product) }

    before(:each) do
      # for clean testing, delete index, create new one and create/update mapping
      Spree::Product.delete_all
      client = Elasticsearch::Client.new log: true, hosts: Spree::ElasticsearchSettings.hosts
      client.indices.create index: Spree::ElasticsearchSettings.index, body: {}
      client.indices.put_mapping index: Spree::ElasticsearchSettings.index, type: Spree::Product.type, body: Spree::Product.mapping
    end

    context "#index" do
      it "updates an existing product in the index" do
        a_product.name = "updated name"
        result = a_product.index
        result['_version'].should == 2
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == 'updated name'
      end
    end

    context 'get' do
      it "retrieves a product form the index" do
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == a_product.name
      end
    end

    context 'search' do
      it "retrieves a product based on name" do
        another_product.name = "Foobar"
        another_product.index
        sleep 3 # allow some time for elasticsearch
        products = Spree::Product.search(name: another_product.name)
        products.total.should == 1
        products.any?{ |p| p.name == another_product.name }.should be_true
      end

      it "retrieves products based on part of the name" do
        a_product.name = "Product 1"
        another_product.name = "Product 2"
        a_product.index
        another_product.index
        sleep 3 # allow some time for elasticsearch
        products = Spree::Product.search(name: 'Product')
        products.total.should == 2
        products.any?{ |p| p.name == a_product.name }.should be_true
        products.any?{ |p| p.name == another_product.name }.should be_true
      end

      it "retrieves products default sorted on name" do
        a_product.name = "Product 1"
        a_product.index
        another_product.name = "Product 2"
        another_product.index
        sleep 3 # allow some time for elasticsearch
        products = Spree::Product.search
        products.total.should == 2
        products.to_a[0].name.should == a_product.name
        products.to_a[1].name.should == another_product.name
      end

      context 'properties' do
        it "allows searching on property" do
          a_product.set_property('the_prop', 'a_value')
          product = Spree::Product.find(a_product.id)
          product.save
          sleep 3 # allow some time for elasticsearch
          products = Spree::Product.search(properties: [{ 'the_prop' => 'a_value' }])
          products.count.should == 1
          products.to_a[0].name.should == product.name
        end
      end

      context 'facets' do
        it "contains price facet" do
          products = Spree::Product.search(name: a_product.name)
          facet = products.facets.find {|facet| facet.name == "price"}
          facet.should_not be_nil
          facet.type.should == "statistical"
        end

        it "contains taxons facet" do
          taxon = create(:taxon)
          a_product.taxons << taxon
          a_product.save
          sleep 3 # allow some time for elasticsearch
          products = Spree::Product.search(name: a_product.name)
          facet = products.facets.find {|facet| facet.name == "taxons"}
          facet.should_not be_nil
          facet.type.should == "terms"
        end
      end
    end

    context "update_index" do
      it "indexes when saved and available" do
        a_product = build(:product)
        a_product.save
        sleep 1
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == a_product.name
      end

      it "removes from index when saved and not available" do
        a_product.available_on = Time.now + 1.day
        a_product.save
        sleep 1
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == a_product.name
      end

      it "removes from index when saved and deleted" do
        a_product.destroy
        sleep 1
        expect { Product.get(a_product.id) }.to raise_error(Elasticsearch::Transport::Transport::Errors::NotFound)
      end
    end

    context 'type' do
      it 'returns the name of the class' do
        Product.type.should == 'spree_product'
      end
    end

  end
end