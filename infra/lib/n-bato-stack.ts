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

    new cdk.CfnOutput(this, 'StaticIpAddress', { value: staticIp.attrIpAddress });
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
}
