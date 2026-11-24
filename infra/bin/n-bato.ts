#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { NBatoStack } from '../lib/n-bato-stack';

// アカウントはリポジトリに書かず、実行する人の AWS のプロファイルから決める(AWS_PROFILE)。
const app = new cdk.App();
new NBatoStack(app, 'NBatoStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: 'ap-northeast-1' },
  description: 'n-bato production (Lightsail + S3 backup + SES)',
});
cdk.Tags.of(app).add('Project', 'n-bato');
