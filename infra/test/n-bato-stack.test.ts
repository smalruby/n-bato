import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { NBatoStack } from '../lib/n-bato-stack';

const template = Template.fromStack(new NBatoStack(new cdk.App(), 'Test', { env: { account: '111111111111', region: 'ap-northeast-1' } }));

test('Lightsail は 2GB で、22/80/443 だけを開け、毎日スナップショットを取る', () => {
  template.hasResourceProperties('AWS::Lightsail::Instance', {
    BundleId: 'small_3_0',
    KeyPairName: 'n-bato-deploy',
    Networking: { Ports: [Match.objectLike({ FromPort: 22 }), Match.objectLike({ FromPort: 80 }), Match.objectLike({ FromPort: 443 })] },
    AddOns: [Match.objectLike({ AddOnType: 'AutoSnapshot', Status: 'Enabled' })],
  });
});

test('サーバー・静的 IP・バケットは、スタックを消しても残す', () => {
  template.hasResource('AWS::Lightsail::Instance', { DeletionPolicy: 'Retain' });
  template.hasResource('AWS::Lightsail::StaticIp', { DeletionPolicy: 'Retain' });
  template.hasResource('AWS::S3::Bucket', { DeletionPolicy: 'Retain' });
});

test('バックアップは非公開で、30 日で消える', () => {
  template.hasResourceProperties('AWS::S3::Bucket', {
    PublicAccessBlockConfiguration: { BlockPublicAcls: true, BlockPublicPolicy: true, IgnorePublicAcls: true, RestrictPublicBuckets: true },
    LifecycleConfiguration: { Rules: [Match.objectLike({ ExpirationInDays: 30, Status: 'Enabled' })] },
  });
});

test('アクセスキーはスタックに入れない', () => {
  template.resourceCountIs('AWS::IAM::AccessKey', 0);
  template.resourceCountIs('AWS::IAM::User', 2);
});

test('SES の送信は smalruby.jp の差出人だけ', () => {
  template.hasResourceProperties('AWS::SES::EmailIdentity', { EmailIdentity: 'smalruby.jp' });
  template.hasResourceProperties('AWS::IAM::Policy', {
    PolicyDocument: { Statement: [Match.objectLike({ Action: 'ses:SendRawEmail', Condition: { StringLike: { 'ses:FromAddress': ['*@smalruby.jp'] } } })] },
  });
});
