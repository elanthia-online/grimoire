require 'spec_helper'

RSpec.describe Grimoire::CommandRewrite do
  it 'rewrites a leading dot into the Lich script prefix' do
    expect(described_class.call('.foo')).to eq(';foo')
  end

  it 'leaves commands without a leading dot untouched' do
    expect(described_class.call('look')).to eq('look')
  end

  it 'passes an explicit Lich prefix through unchanged' do
    expect(described_class.call(';foo')).to eq(';foo')
  end

  it 'passes an empty string through unchanged' do
    expect(described_class.call('')).to eq('')
  end

  it 'rewrites a bare dot to a bare Lich prefix' do
    expect(described_class.call('.')).to eq(';')
  end

  it 'only rewrites the leading dot when there are several' do
    expect(described_class.call('..foo')).to eq(';.foo')
  end
end
