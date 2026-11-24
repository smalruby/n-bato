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

describe('GitHub Actions の役割(OIDC、docs/adr/0036)', () => {
  const issuer = 'token.actions.githubusercontent.com';
  const trust = (subjects: string[]) => ({
    AssumeRolePolicyDocument: {
      Statement: [Match.objectLike({
        Action: 'sts:AssumeRoleWithWebIdentity',
        Condition: { StringEquals: { [`${issuer}:aud`]: 'sts.amazonaws.com', [`${issuer}:sub`]: subjects } },
      })],
    },
  });
  const actionsOf = (t: Template, roleLogicalId: string) => {
    const policies = t.findResources('AWS::IAM::Policy');
    return Object.values(policies)
      .filter((p: any) => (p.Properties.Roles ?? []).some((r: any) => String(r.Ref).startsWith(roleLogicalId)))
      .flatMap((p: any) => p.Properties.PolicyDocument.Statement.flatMap((s: any) => [s.Action].flat()))
      .sort();
  };

  test('GitHub の OIDC プロバイダを作る(長く使う鍵は置かない)', () => {
    template.resourceCountIs('AWS::IAM::OIDCProvider', 1);
    template.hasResourceProperties('AWS::IAM::OIDCProvider', { Url: `https://${issuer}`, ClientIdList: ['sts.amazonaws.com'] });
  });

  test('すでにあるプロバイダを使うときは作らない', () => {
    const app = new cdk.App({ context: { githubOidcProviderArn: `arn:aws:iam::111111111111:oidc-provider/${issuer}` } });
    const t = Template.fromStack(new NBatoStack(app, 'Test', { env: { account: '111111111111', region: 'ap-northeast-1' } }));
    t.resourceCountIs('AWS::IAM::OIDCProvider', 0);
    t.resourceCountIs('AWS::IAM::Role', 2);
  });

  test('差分を出す役割は smalruby/n-bato の PR と main だけが使え、読むことしかできない', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'n-bato-github-cdk-diff',
      ...trust(['repo:smalruby/n-bato:pull_request', 'repo:smalruby/n-bato:ref:refs/heads/main']),
    });
    expect(actionsOf(template, 'CdkDiffRole')).toEqual([
      'cloudformation:DescribeStacks', 'cloudformation:GetTemplate', 'cloudformation:GetTemplateSummary', 'cloudformation:ListStackResources',
      'ssm:GetParameter', 'ssm:GetParameters',
    ]);
  });

  test('反映する役割は Environment production-infra のジョブだけが使え、CDK の bootstrap の役割を引き受けるだけ', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'n-bato-github-cdk-deploy',
      ...trust(['repo:smalruby/n-bato:environment:production-infra']),
    });
    expect(actionsOf(template, 'CdkDeployRole')).toEqual(['sts:AssumeRole', 'sts:TagSession']);
    const policy = Object.values(template.findResources('AWS::IAM::Policy'))
      .find((p: any) => (p.Properties.Roles ?? []).some((r: any) => String(r.Ref).startsWith('CdkDeployRole')));
    expect(JSON.stringify(policy)).toContain(':iam::111111111111:role/cdk-hnb659fds-*-role-111111111111-ap-northeast-1');
  });
});
