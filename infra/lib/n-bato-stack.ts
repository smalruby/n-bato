import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lightsail from 'aws-cdk-lib/aws-lightsail';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ses from 'aws-cdk-lib/aws-ses';
import { Construct } from 'constructs';

/**
 * n-bato の本番(デプロイの相談 第1〜3回で決めたこと)。
 *
 * - Lightsail 2GB・東京。22/80/443 はどこからでも(SSH は鍵だけ)。毎日の自動スナップショット。
 * - S3 に毎晩の SQLite と添付の写し(30 日で消す)。書き込むのはバックアップ用の IAM ユーザー。
 * - SES: 差出人のドメイン smalruby.jp(DKIM の CNAME は人がお名前.com に足す)。送るのは SES 用の IAM ユーザー。
 *
 * 秘密(アクセスキー・SMTP のパスワード)と SSH の公開鍵の登録は、スタックに入れず bin/infra-credentials で行う。
 */
export const INSTANCE_NAME = 'n-bato-prod';
export const KEY_PAIR_NAME = 'n-bato-deploy';
export const MAIL_DOMAIN = 'smalruby.jp';
export const BACKUP_PREFIX = 'n-bato/';
export const BACKUP_RETENTION_DAYS = 30;
// GitHub Actions の OIDC で信じるリポジトリと、役割の名前(staging を足すときも production の名前は変えない)
export const GITHUB_REPOSITORY = 'smalruby/n-bato';
export const CDK_DIFF_ROLE_NAME = 'n-bato-github-cdk-diff';
export const CDK_DEPLOY_ROLE_NAME = 'n-bato-github-cdk-deploy';
// cdk deploy のジョブの Environment。承認者が要るので、アプリのデプロイ(Environment「production」、承認なし)とは分ける
export const CDK_DEPLOY_ENVIRONMENT = 'production-infra';

export class NBatoStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const port = (p: number) => ({ fromPort: p, toPort: p, protocol: 'tcp', cidrs: ['0.0.0.0/0'], ipv6Cidrs: ['::/0'] });

    // user data を変えるとサーバーが作り直される(データが消える)ので、作ったあとは変えない。
    const instance = new lightsail.CfnInstance(this, 'Server', {
      instanceName: INSTANCE_NAME,
      blueprintId: 'ubuntu_24_04',
      bundleId: 'small_3_0',
      availabilityZone: `${this.region}a`,
      keyPairName: KEY_PAIR_NAME,
      networking: { ports: [port(22), port(80), port(443)] },
      addOns: [{
        addOnType: 'AutoSnapshot',
        status: 'Enabled',
        // UTC。日本の 3:00
        autoSnapshotAddOnRequest: { snapshotTimeOfDay: '18:00' },
      }],
      userData: [
        '#!/bin/bash',
        'set -eu',
        // PDF の Chrome が重なったときの逃げ場(2GB)
        'fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile',
        "echo '/swapfile none swap sw 0 0' >> /etc/fstab",
      ].join('\n'),
    });
    instance.applyRemovalPolicy(cdk.RemovalPolicy.RETAIN);

    const staticIp = new lightsail.CfnStaticIp(this, 'StaticIp', {
      staticIpName: `${INSTANCE_NAME}-ip`,
      attachedTo: instance.instanceName,
    });
    staticIp.addResourceDependency(instance);
    staticIp.applyRemovalPolicy(cdk.RemovalPolicy.RETAIN);

    const backupBucket = new s3.Bucket(this, 'BackupBucket', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [{ expiration: cdk.Duration.days(BACKUP_RETENTION_DAYS) }],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const backupUser = new iam.User(this, 'BackupUser');
    backupUser.addToPolicy(new iam.PolicyStatement({
      actions: ['s3:PutObject', 's3:GetObject'],
      resources: [backupBucket.arnForObjects(`${BACKUP_PREFIX}*`)],
    }));
    backupUser.addToPolicy(new iam.PolicyStatement({
      actions: ['s3:ListBucket'],
      resources: [backupBucket.bucketArn],
      conditions: { StringLike: { 's3:prefix': [`${BACKUP_PREFIX}*`] } },
    }));

    const mailIdentity = new ses.EmailIdentity(this, 'MailDomain', {
      identity: ses.Identity.domain(MAIL_DOMAIN),
    });

    const mailUser = new iam.User(this, 'MailUser');
    mailUser.addToPolicy(new iam.PolicyStatement({
      actions: ['ses:SendRawEmail'],
      resources: [`arn:${this.partition}:ses:${this.region}:${this.account}:identity/${MAIL_DOMAIN}`],
      conditions: { StringLike: { 'ses:FromAddress': [`*@${MAIL_DOMAIN}`] } },
    }));
    mailUser.node.addDependency(mailIdentity);

    const github = this.githubActionsRoles();

    new cdk.CfnOutput(this, 'StaticIpAddress', { value: staticIp.attrIpAddress });
    new cdk.CfnOutput(this, 'CdkDiffRoleArn', { value: github.diffRole.roleArn });
    new cdk.CfnOutput(this, 'CdkDeployRoleArn', { value: github.deployRole.roleArn });
    new cdk.CfnOutput(this, 'BackupBucketName', { value: backupBucket.bucketName });
    new cdk.CfnOutput(this, 'BackupUserName', { value: backupUser.userName });
    new cdk.CfnOutput(this, 'MailUserName', { value: mailUser.userName });
    // お名前.com に足す DKIM の CNAME(名前 → 値)
    [1, 2, 3].forEach((n) => {
      const name = (mailIdentity as any)[`dkimDnsTokenName${n}`] as string;
      const value = (mailIdentity as any)[`dkimDnsTokenValue${n}`] as string;
      new cdk.CfnOutput(this, `MailDkim${n}`, { value: cdk.Fn.join(' CNAME ', [name, value]) });
    });
  }

  /**
   * GitHub Actions が CDK を扱う役割(開発QAボード 第6回 r6-cdk、docs/adr/0036)。長く使う鍵は置かない(OIDC)。
   *
   * - 差分を出す役割: PR と main への push から。読むだけ(NBatoStack のテンプレートと、bootstrap の版)。
   *   バックアップのバケットの中身などは読めない(ReadOnlyAccess は使わない)。
   * - 反映する役割: Environment「production-infra」のジョブ(人の承認のあと)からだけ。できるのは CDK の
   *   bootstrap の役割(cdk-<qualifier>-*-role)を引き受けることだけで、実際の変更は CloudFormation が行う。
   *
   * どちらも、信じるのはリポジトリ smalruby/n-bato だけ(ADR-0035 と同じく、用途ごとに分けて絞る)。
   * 同じアカウントにすでに GitHub の OIDC プロバイダがあるときは、`-c githubOidcProviderArn=<ARN>` でそれを使う
   *(1 つのアカウントに同じ URL のプロバイダは 1 つしか作れない)。
   */
  private githubActionsRoles() {
    const issuer = 'token.actions.githubusercontent.com';
    const existingProviderArn = this.node.tryGetContext('githubOidcProviderArn') as string | undefined;
    const provider = existingProviderArn
      ? iam.OidcProviderNative.fromOidcProviderArn(this, 'GitHubOidc', existingProviderArn)
      : new iam.OidcProviderNative(this, 'GitHubOidc', { url: `https://${issuer}`, clientIds: ['sts.amazonaws.com'] });

    const principal = (subjects: string[]) => new iam.OpenIdConnectPrincipal(provider, {
      StringEquals: {
        [`${issuer}:aud`]: 'sts.amazonaws.com',
        [`${issuer}:sub`]: subjects.map((s) => `repo:${GITHUB_REPOSITORY}:${s}`),
      },
    });

    const diffRole = new iam.Role(this, 'CdkDiffRole', {
      roleName: CDK_DIFF_ROLE_NAME,
      description: 'GitHub Actions (smalruby/n-bato): cdk diff only (read-only)',
      assumedBy: principal(['pull_request', 'ref:refs/heads/main']),
      maxSessionDuration: cdk.Duration.hours(1),
    });
    diffRole.addToPolicy(new iam.PolicyStatement({
      actions: ['cloudformation:DescribeStacks', 'cloudformation:GetTemplate', 'cloudformation:GetTemplateSummary', 'cloudformation:ListStackResources'],
      resources: [
        `arn:${this.partition}:cloudformation:${this.region}:${this.account}:stack/${this.stackName}/*`,
        `arn:${this.partition}:cloudformation:${this.region}:${this.account}:stack/CDKToolkit/*`,
      ],
    }));
    const qualifier = cdk.DefaultStackSynthesizer.DEFAULT_QUALIFIER;
    diffRole.addToPolicy(new iam.PolicyStatement({
      actions: ['ssm:GetParameter', 'ssm:GetParameters'],
      resources: [`arn:${this.partition}:ssm:${this.region}:${this.account}:parameter/cdk-bootstrap/${qualifier}/version`],
    }));

    const deployRole = new iam.Role(this, 'CdkDeployRole', {
      roleName: CDK_DEPLOY_ROLE_NAME,
      description: `GitHub Actions (smalruby/n-bato, environment ${CDK_DEPLOY_ENVIRONMENT}): cdk deploy via bootstrap roles`,
      assumedBy: principal([`environment:${CDK_DEPLOY_ENVIRONMENT}`]),
      maxSessionDuration: cdk.Duration.hours(1),
    });
    deployRole.addToPolicy(new iam.PolicyStatement({
      actions: ['sts:AssumeRole', 'sts:TagSession'],
      resources: [`arn:${this.partition}:iam::${this.account}:role/cdk-${qualifier}-*-role-${this.account}-${this.region}`],
    }));

    return { diffRole, deployRole };
  }
}
