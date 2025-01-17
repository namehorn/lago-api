# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsersService, type: :service do
  subject { described_class.new }

  describe 'register' do
    it 'calls SegmentIdentifyJob' do
      allow(SegmentIdentifyJob).to receive(:perform_later)
      result = subject.register('email', 'password', 'organization_name')

      expect(SegmentIdentifyJob).to have_received(:perform_later).with(
        membership_id: "membership/#{result.membership.id}"
      )
    end

    it 'calls SegmentTrackJob' do
      allow(SegmentTrackJob).to receive(:perform_later)
      result = subject.register('email', 'password', 'organization_name')

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: "membership/#{result.membership.id}",
        event: 'organization_registered',
        properties: {
          organization_name: result.organization.name,
          organization_id: result.organization.id
        }
      )
    end
  end

  describe 'login' do
    it 'calls SegmentIdentifyJob' do
      allow(SegmentIdentifyJob).to receive(:perform_later)
      result = subject.register('email', 'password', 'organization_name')

      expect(SegmentIdentifyJob).to have_received(:perform_later).with(
        membership_id: "membership/#{result.user.memberships.first.id}"
      )
    end
  end

  describe 'new_token' do
    let(:user) { create(:user) }

    it 'generates a jwt token for the user' do
      result = subject.new_token(user)

      expect(result).to be_success
      expect(result.user).to eq(user)
      expect(result.token).to be_present
    end
  end
end
